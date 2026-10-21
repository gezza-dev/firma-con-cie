// SPDX-License-Identifier: BSD-3-Clause
#include "card.h"
#include "local_cache.h"
#include "paired_store.h"
#include "snap_public_store.h"
#include <algorithm>
#include <cstring>
#if defined(_WIN32) && !defined(CIE_PAIRING_TEST_SERVICE)
#include "../../pcsc_utf8.h"
#undef SCardListReaders
#undef SCardConnect
#undef SCardGetStatusChange
#define SCardListReaders cie_pcsc::list
#define SCardConnect cie_pcsc::connect
#define SCardGetStatusChange cie_pcsc::change
#endif

namespace cie_linux {
namespace {
void pcsc(LONG status) {
    if (status == SCARD_S_SUCCESS) return;
    if (status == SCARD_E_SHARING_VIOLATION) throw Error(CKR_DEVICE_ERROR);
    if (status == SCARD_E_NO_SMARTCARD || status == SCARD_W_REMOVED_CARD ||
        status == SCARD_W_RESET_CARD || status == SCARD_E_READER_UNAVAILABLE)
        throw Error(CKR_DEVICE_REMOVED);
    throw Error(CKR_DEVICE_ERROR);
}
}
CK_RV mapped(int32_t status) {
    if (!status) return CKR_OK;
    if ((status & 0xfff0) == 0x63c0 || status == 0x6300) return CKR_PIN_INCORRECT;
    if (status == 0x6983) return CKR_PIN_LOCKED;
    if (status == CIE_WEB_AUTH_REQUIRED) return CKR_USER_NOT_LOGGED_IN;
    if (status == CIE_WEB_ALGORITHM) return CKR_DATA_INVALID;
    return CKR_DEVICE_ERROR;
}
Readers::~Readers() { if (context_) SCardReleaseContext(context_); }
std::vector<Reader> Readers::list() {
    if (!context_) {
        auto status = SCardEstablishContext(SCARD_SCOPE_USER, nullptr, nullptr, &context_);
        if (status == SCARD_E_NO_SERVICE || status == SCARD_E_SERVICE_STOPPED) return {};
        pcsc(status);
    }
    DWORD size = 0;
    auto status = SCardListReaders(context_, nullptr, nullptr, &size);
    if (status == SCARD_E_NO_READERS_AVAILABLE) return {};
    if (status == SCARD_E_INVALID_HANDLE || status == SCARD_E_NO_SERVICE || status == SCARD_E_SERVICE_STOPPED) {
        SCardReleaseContext(context_); context_ = 0; return {};
    }
    pcsc(status);
    if (size < 2 || size > 65536) throw Error(CKR_DEVICE_ERROR);
    std::vector<char> names(size, 0);
    pcsc(SCardListReaders(context_, nullptr, names.data(), &size));
    if (size > names.size() || size < 2 || names[size-1] || names[size-2]) throw Error(CKR_DEVICE_ERROR);
    std::vector<Reader> result;
    for (size_t offset = 0; offset + 1 < size && names[offset];) {
        auto length = strnlen(names.data()+offset, size-offset);
        if (!length || length >= size-offset || result.size() == 64) throw Error(CKR_DEVICE_ERROR);
        Reader reader{std::string(names.data()+offset, length), {}};
        SCARD_READERSTATE state{}; state.szReader = reader.name.c_str(); state.dwCurrentState = SCARD_STATE_UNAWARE;
        status = SCardGetStatusChange(context_, 0, &state, 1);
        if (status == SCARD_S_SUCCESS && (state.dwEventState & SCARD_STATE_PRESENT) &&
            !(state.dwEventState & (SCARD_STATE_MUTE | SCARD_STATE_UNAVAILABLE)) &&
            state.cbAtr && state.cbAtr <= sizeof(state.rgbAtr))
            reader.atr.assign(state.rgbAtr, state.rgbAtr+state.cbAtr);
        result.push_back(std::move(reader)); offset += length+1;
    }
    return result;
}
void Card::release() noexcept {
    if (session_) { cie_web_close(session_); session_ = nullptr; }
    // Reset clears the card's authentication, not just our local flag.
    LONG resetStatus = SCARD_S_SUCCESS;
    if (transaction_) { resetStatus = SCardEndTransaction(handle_, SCARD_RESET_CARD); transaction_ = false; }
    if (handle_) { SCardDisconnect(handle_, resetStatus == SCARD_S_SUCCESS ? SCARD_LEAVE_CARD : SCARD_RESET_CARD); handle_ = 0; }
    if (context_) { SCardReleaseContext(context_); context_ = 0; }
}
Card::~Card() { release(); }
Card::Card(const std::string& reader, const std::string& expected, const std::vector<uint8_t>& known) {
    try {
        if (cie_web_abi_version() != 1) throw Error(CKR_DEVICE_ERROR);
        pcsc(SCardEstablishContext(SCARD_SCOPE_USER, nullptr, nullptr, &context_));
        // Exclusive connect fails promptly if another application owns the card;
        // do not queue behind its transaction or reset/reconnect its context.
        pcsc(SCardConnect(context_, reader.c_str(), SCARD_SHARE_EXCLUSIVE,
                          SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &handle_, &protocol_));
        pcsc(SCardBeginTransaction(handle_)); transaction_ = true;
        unsigned char atr[64]{}; DWORD atrSize = sizeof(atr), state = 0, n = 4096; char name[4096]{};
        pcsc(SCardStatus(handle_, name, &n, &state, &protocol_, atr, &atrSize));
        if (!atrSize || atrSize > sizeof(atr)) throw Error(CKR_DEVICE_ERROR);
        atr_.assign(atr, atr+atrSize);
        auto status = cie_web_open(atr, atrSize, transmit, this, expected.empty()?nullptr:expected.c_str(), &session_);
        if (status) throw Error(mapped(status));
        char identifier[64]{}; uint32_t length = sizeof(identifier);
        if (cie_web_identifier(session_, identifier, &length) || !length || length > sizeof(identifier) ||
            identifier[length-1] || !cie_pairing::validId(identifier)) throw Error(CKR_DEVICE_ERROR);
        id = identifier;
        std::vector<uint8_t> saved = known;
        if (saved.empty()) {
          #ifndef _WIN32
          if (cie_linux_snap::running()) {
            saved = cie_linux_snap::read(id);
            if (saved.empty()) throw Error(CKR_DEVICE_ERROR);
          } else
#endif
          {
            // Read only the public Web namespace. Never read a PIN-prefix record.
            cie_cache::Store store; auto bytes = store.read("web", id);
            saved.assign(bytes.begin(), bytes.end());
          }
        }
        if (!saved.empty() && cie_web_set_certificate(session_, saved.data(), uint32_t(saved.size())))
            throw Error(CKR_DEVICE_ERROR);
        uint8_t der[8192]{}; length = sizeof(der);
        if (cie_web_certificate(session_, der, &length) || !length || length > sizeof(der))
            throw Error(CKR_DEVICE_ERROR);
        certificate.assign(der, der+length);
    } catch (...) { release(); throw; }
}
void Card::check() {
    unsigned char atr[64]{}; char name[4096]{}; DWORD n=sizeof(name), a=sizeof(atr), state=0, protocol=0;
    pcsc(SCardStatus(handle_, name, &n, &state, &protocol, atr, &a));
    if (protocol != protocol_ || a != atr_.size() || a > sizeof(atr) ||
        !std::equal(atr_.begin(), atr_.end(), atr)) throw Error(CKR_DEVICE_REMOVED);
}
int32_t Card::transmit(void* context, const uint8_t* data, uint32_t size, uint8_t* out, uint32_t* count) {
    auto& card = *static_cast<Card*>(context); DWORD length = *count;
    const auto* pci = card.protocol_ == SCARD_PROTOCOL_T1 ? SCARD_PCI_T1 : SCARD_PCI_T0;
    auto status = SCardTransmit(card.handle_, pci, data, size, nullptr, out, &length);
    *count = length; return status == SCARD_S_SUCCESS ? CIE_WEB_OK : CIE_WEB_TRANSPORT;
}
CK_RV Card::authenticate(char* pin) { check(); return mapped(cie_web_authenticate(session_, pin, 8)); }
CK_RV Card::sign(const std::vector<uint8_t>& data, uint8_t* signature, uint32_t* size) {
    check(); return mapped(cie_web_sign(session_, data.data(), uint32_t(data.size()), signature, size));
}
}
