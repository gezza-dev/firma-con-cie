// SPDX-License-Identifier: BSD-3-Clause
// The Flutter backend always receives the full PIN. It neither imports nor
// persists the legacy PIN-fragment cache of the system middleware.
#include <vector>
#include <stdint.h>
#include <stdexcept>
bool CacheExists(const char*) { return false; }
bool CacheRemove(const char*) { return false; }
void CacheGetCertificate(const char*, std::vector<uint8_t>&) { throw std::runtime_error("Cache non disponibile in questa applicazione: usare il PIN completo"); }
void CacheGetPIN(const char*, std::vector<uint8_t>&) { throw std::runtime_error("Memorizzazione del PIN disabilitata in questa applicazione"); }
void CacheSetData(const char*, uint8_t*, int, uint8_t*, int) { throw std::runtime_error("Abbinamento persistente non disponibile in questa applicazione"); }
