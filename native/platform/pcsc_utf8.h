// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#ifdef _WIN32
#include <windows.h>
#include <winscard.h>
#include <string>
#include <vector>
#include <cstring>
#include <stdexcept>
namespace cie_pcsc {
inline std::wstring wide(const char* text) {
    if (!text) throw std::invalid_argument("reader");
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, nullptr, 0);
    if (!n) throw std::invalid_argument("UTF-8");
    std::wstring value(n, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, value.data(), n);
    value.pop_back(); return value;
}
inline LONG list(SCARDCONTEXT context, const char* groups, char* output, DWORD* size) noexcept {
    try {
        if (groups || !size || *size == SCARD_AUTOALLOCATE) return SCARD_E_INVALID_PARAMETER;
        DWORD n = 0;
        LONG status = SCardListReadersW(context, nullptr, nullptr, &n);
        if (status != SCARD_S_SUCCESS) return status;
        if (n > 1024 * 1024) return SCARD_E_NO_MEMORY;
        std::vector<wchar_t> readers(n);
        status = SCardListReadersW(context, nullptr, readers.data(), &n);
        if (status != SCARD_S_SUCCESS) return status;
        int bytes = WideCharToMultiByte(CP_UTF8, 0, readers.data(), n, nullptr, 0, nullptr, nullptr);
        if (bytes <= 0) return SCARD_E_INVALID_VALUE;
        DWORD available = *size; *size = static_cast<DWORD>(bytes);
        if (!output) return SCARD_S_SUCCESS;
        if (available < *size) return SCARD_E_INSUFFICIENT_BUFFER;
        WideCharToMultiByte(CP_UTF8, 0, readers.data(), n, output, bytes, nullptr, nullptr);
        return SCARD_S_SUCCESS;
    } catch (...) { return SCARD_E_NO_MEMORY; }
}
inline LONG connect(SCARDCONTEXT context, const char* reader, DWORD share, DWORD protocols, SCARDHANDLE* card, DWORD* active) noexcept {
    try { return SCardConnectW(context, wide(reader).c_str(), share, protocols, card, active); }
    catch (...) { return SCARD_E_INVALID_PARAMETER; }
}
inline LONG change(SCARDCONTEXT context, DWORD timeout, SCARD_READERSTATEA* states, DWORD count) noexcept {
    try {
        if ((!states && count) || count > 4096) return SCARD_E_INVALID_PARAMETER;
        std::vector<std::wstring> names; names.reserve(count);
        std::vector<SCARD_READERSTATEW> converted(count);
        for (DWORD i = 0; i < count; ++i) {
            names.push_back(wide(states[i].szReader));
            auto& to = converted[i]; auto& from = states[i];
            to.szReader = names.back().c_str(); to.pvUserData = from.pvUserData;
            to.dwCurrentState = from.dwCurrentState;
        }
        LONG status = SCardGetStatusChangeW(context, timeout, converted.data(), count);
        if (status == SCARD_S_SUCCESS) for (DWORD i = 0; i < count; ++i) {
            states[i].dwEventState = converted[i].dwEventState;
            states[i].cbAtr = converted[i].cbAtr;
            std::memcpy(states[i].rgbAtr, converted[i].rgbAtr, sizeof(states[i].rgbAtr));
        }
        return status;
    } catch (...) { return SCARD_E_INVALID_PARAMETER; }
}
}
#endif
