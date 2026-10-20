// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "pkcs11_api.h"
#include "cie_web.h"
#include <winscard.h>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace cie_linux {
struct Error : std::runtime_error {
    CK_RV code;
    explicit Error(CK_RV value) : std::runtime_error("CIE PKCS11 operation failed"), code(value) {}
};
CK_RV mapped(int32_t status);
struct Reader { std::string name; std::vector<uint8_t> atr; };
class Readers {
    SCARDCONTEXT context_ = 0;
public:
    ~Readers();
    std::vector<Reader> list();
};
// One exclusive connection/transaction owns the IAS context. It is never
// reconnected or retried. The provider releases it on logout, failure or idle.
class Card {
    SCARDCONTEXT context_ = 0;
    SCARDHANDLE handle_ = 0;
    DWORD protocol_ = 0;
    std::vector<uint8_t> atr_;
    bool transaction_ = false;
    CieWebSession* session_ = nullptr;
    static int32_t transmit(void*, const uint8_t*, uint32_t, uint8_t*, uint32_t*);
    void release() noexcept;
public:
    std::string id;
    std::vector<uint8_t> certificate;
    Card(const std::string& reader, const std::string& expected = {},
         const std::vector<uint8_t>& knownCertificate = {});
    ~Card();
    Card(const Card&) = delete;
    Card& operator=(const Card&) = delete;
    void check();
    CK_RV authenticate(char* pin);
    CK_RV sign(const std::vector<uint8_t>& data, uint8_t* signature, uint32_t* size);
};
}
