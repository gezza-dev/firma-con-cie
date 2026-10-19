// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <openssl/crypto.h>
#include <openssl/provider.h>
#include <openssl/opensslv.h>

#if OPENSSL_VERSION_MAJOR != 3 || OPENSSL_VERSION_MINOR < 5
#error "This fork requires supported OpenSSL 3.5 or newer in the 3.x series"
#endif

namespace cie {
// Providers are compiled into libcrypto (Configure no-module) and retained for
// the process lifetime. No installation-specific module/config path is needed.
// Legacy ciphers support existing encrypted PDF files; TLS security is not lowered.
inline bool initializeOpenSsl()
{
    static const bool ready = [] {
        if (OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG, nullptr) != 1)
            return false;
        OSSL_PROVIDER* standard = OSSL_PROVIDER_load(nullptr, "default");
        if (!standard) return false;
        OSSL_PROVIDER* legacy = OSSL_PROVIDER_load(nullptr, "legacy");
        if (!legacy) { OSSL_PROVIDER_unload(standard); return false; }
        return true;
    }();
    return ready;
}
}
