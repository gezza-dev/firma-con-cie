// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace cie_identification {
// Identification needs only SELECT, READ BINARY and GET RESPONSE. Reject
// authentication, writes, proprietary reset controls and unbounded read loops.
class ReadCommands {
    unsigned count_ = 0;
public:
    bool accept(const uint8_t* apdu, size_t size) {
        if (!apdu || size < 4 || apdu[0] != 0 ||
            (apdu[1] != 0xA4 && apdu[1] != 0xB0 && apdu[1] != 0xC0)) return false;
        if (count_ >= 16) return false;
        ++count_;
        return true;
    }
};

inline std::string identifier(const uint8_t* bytes, size_t size) {
    if (!bytes || !size) throw std::runtime_error("Identificativo CIE non valido");
    while (size && bytes[size - 1] == 0) --size;
    if (!size || size >= 64) throw std::runtime_error("Identificativo CIE non valido");
    return std::string(reinterpret_cast<const char*>(bytes), size);
}

template<class Session, class Buffer>
std::string readIdentifier(Session& session) {
    // Establish the family-specific parent application first (MF or IAS).
    // Direct CIE selection can return 6A82 when a previous client left an EF
    // selected. This is deterministic public navigation, never a reset/retry.
    session.SelectAID_IAS();
    session.SelectAID_CIE();
    Buffer services;
    session.ReadIdServizi(services);
    return identifier(services.data(), services.size());
}
}
