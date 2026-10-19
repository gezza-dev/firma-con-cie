// SPDX-License-Identifier: BSD-3-Clause
#include "card_identification.h"
#include <iostream>
#include <vector>

struct PublicSession {
    bool parent = false, cie = false;
    unsigned calls = 0;
    void SelectAID_IAS() { parent = true; cie = false; ++calls; }
    void SelectAID_CIE() {
        if (!parent) throw std::runtime_error("6A82: select parent first");
        cie = true; ++calls;
    }
    void ReadIdServizi(std::vector<uint8_t>& buffer) {
        if (!cie) throw std::runtime_error("CIE not selected");
        buffer = {'T', 'E', 'S', 'T', 0}; ++calls;
    }
    // No reset, PAN, authentication or write operation is available here.
};

int main() {
    unsigned checks = 0;
    auto require = [&](bool value) { ++checks; if (!value) throw std::runtime_error("Identification test failed"); };
    cie_identification::ReadCommands commands;
    uint8_t apdu[] = {0, 0xA4, 4, 0x0C, 0};
    require(!commands.accept(nullptr, 5));
    require(!commands.accept(apdu, 2)); // Legacy reset controls cannot pass.
    for (uint8_t ins : {0x20, 0x24, 0x2C, 0xD6, 0xDA, 0x82}) {
        apdu[1] = ins;
        require(!commands.accept(apdu, sizeof(apdu))); // PIN/PUK, writes, auth.
    }
    apdu[1] = 0xA4; apdu[0] = 0x0C;
    require(!commands.accept(apdu, sizeof(apdu))); // Secure/proprietary CLA.
    apdu[0] = 0;
    for (unsigned i = 0; i < 16; ++i) {
        apdu[1] = i % 3 == 0 ? 0xA4 : i % 3 == 1 ? 0xB0 : 0xC0;
        require(commands.accept(apdu, sizeof(apdu)));
    }
    require(!commands.accept(apdu, sizeof(apdu))); // Endless EOF/GET RESPONSE.
    uint8_t id[] = {'T', 'E', 'S', 'T', 0, 0};
    require(cie_identification::identifier(id, sizeof(id)) == "TEST");
    auto rejected = [&](const uint8_t* bytes, size_t size) {
        try { cie_identification::identifier(bytes, size); return false; }
        catch (const std::runtime_error&) { return true; }
    };
    require(rejected(nullptr, 4)); require(rejected(id, 0));
    uint8_t empty[] = {0, 0}; require(rejected(empty, 2));
    std::vector<uint8_t> longId(64, 'A'); require(rejected(longId.data(), 64));
    longId.back() = 0; require(cie_identification::identifier(longId.data(), 64).size() == 63);
    PublicSession previousEf;
    bool directRejected = false;
    try { previousEf.SelectAID_CIE(); } catch (const std::runtime_error&) { directRejected = true; }
    require(directRejected);
    require(cie_identification::readIdentifier<PublicSession, std::vector<uint8_t>>(previousEf) == "TEST");
    require(previousEf.calls == 3);
    PublicSession alreadyAtParent; alreadyAtParent.parent = true;
    require(cie_identification::readIdentifier<PublicSession, std::vector<uint8_t>>(alreadyAtParent) == "TEST");
    require(alreadyAtParent.calls == 3);
    std::cout << checks << " read-only identification checks passed\n";
}
