#pragma once

#ifdef CIE_LEGACY_WINDOWS
#include <bcrypt.h>
#define SHA_DIGEST_LENGTH 20
#else
#include <openssl/sha.h>
#endif

#include "../Util/Array.h"

#define SHA256_DIGEST_LENGTH 32

class CSHA256
{
    
public:
	ByteDynArray Digest(ByteArray &data);
    
#ifndef CIE_LEGACY_WINDOWS
    
    void Init();
    void Update(ByteArray data);
    ByteDynArray Final();

    bool isInit;
    SHA256_CTX ctx;
#endif

};
