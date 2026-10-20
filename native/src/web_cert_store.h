// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstdint>
#include <string>
#include <vector>
namespace cie_web_store {
// Public enrollment certificate only. No PIN, prefix or private key.
// Read-only registration/ownership observations; never performs a private key call.
bool componentAvailable();
std::vector<std::string> list();
bool provisioned(const std::string& id,const uint8_t* der,uint32_t size);
std::vector<uint8_t> read(const std::string& id);
void write(const std::string& id,const uint8_t* der,uint32_t size);
void erase(const std::string& id);
// Explicit local challenge via Windows Smart Card KSP; unsupported on Linux
// (Firefox owns authentication). The Windows PIN dialog belongs to
// the OS. No PIN argument, document, site login or network connection.
int32_t test(const std::string& id);
}
