// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace cie_linux_snap {
// Standard Firefox Snap only. Paths are derived from getpwuid, never supplied
// by a browser/environment path override. No Firefox profiles are opened.
bool running();
bool installed();
// Publication contains only DER public certificates. No pairing/cache keys.
bool publish(const std::string& id, const uint8_t* der, uint32_t size);
std::vector<uint8_t> read(const std::string& id);
bool matches_if_installed(const std::string& id, const uint8_t* der, uint32_t size);
void erase(const std::string& id);
}
