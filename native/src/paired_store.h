// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>
#include <stdexcept>
#include <algorithm>
namespace cie_pairing {
// Stable per-user file-cache scope, separate from official middleware and OS credentials.
#ifdef CIE_PAIRING_TEST_SERVICE
inline constexpr const char* service="it.giancarloezza.CIEID.FlutterPrototype.pairing.tests.v1";
#else
inline constexpr const char* service="it.giancarloezza.CIEID.FlutterPrototype.pairing.v1";
#endif
inline bool validId(const std::string& id) {
 return !id.empty() && id.size()<=63 && std::all_of(id.begin(),id.end(),[](unsigned char c){return (c>='0'&&c<='9')||(c>='A'&&c<='Z')||(c>='a'&&c<='z');});
}
struct Secret {
 std::array<char,9> bytes{};
 Secret()=default;Secret(const Secret&)=delete;Secret& operator=(const Secret&)=delete;
 ~Secret(){volatile char* p=bytes.data();for(size_t i=0;i<bytes.size();++i)p[i]=0;}
};
inline void checkId(const std::string& id){if(!validId(id))throw std::runtime_error("pairing_invalid_id");}
struct StoreError : std::runtime_error {
 int64_t nativeCode;
 explicit StoreError(int64_t code):std::runtime_error("pairing_store_unavailable"),nativeCode(code){}
};
// Nonsecret, durable invalidation independent of the protected prefix store.
// Only a newly authenticated, successfully saved pairing may clear it.
bool invalidated(const std::string& id);
void invalidate(const std::string& id);
void acceptFreshPairing(const std::string& id);
std::vector<std::string> invalidatedCards();
bool supported();
void prepare();
// Removes a complete cache record without decrypting it. Works even if its
// key or encrypted contents are damaged. No legacy credential-store fallback.
void eraseRecord(const std::string& id);
// Versioned authenticated public material, separate namespace from PIN prefixes.
std::vector<uint8_t> readPublic(const std::string& id);
void writePublic(const std::string& id,const std::vector<uint8_t>& value);
void erasePublic(const std::string& id);
// Compatibility for field-level cleanup; whole-card removal uses eraseRecord.
void eraseForRemoval(const std::string& id,bool publicData);
std::vector<std::string> listPublic();
// Prefix never crosses the native ABI. File payloads use encrypt-then-MAC.
bool read(const std::string& id,Secret& prefix);
void write(const std::string& id,const char* prefix);
void erase(const std::string& id);
std::vector<std::string> list();
}
