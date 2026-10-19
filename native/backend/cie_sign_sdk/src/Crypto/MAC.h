#pragma once
#ifdef CIE_LEGACY_WINDOWS
#include "..\stdafx.h"
#include <bcrypt.h>
#else
#include <openssl/des.h>
#endif
#include "../Util/util.h"
#include "../Util/UtilException.h"

class CMAC
{
#ifdef CIE_LEGACY_WINDOWS
	BCRYPT_KEY_HANDLE key1;
	BCRYPT_KEY_HANDLE key2;
	ByteDynArray iv;

#else
	DES_key_schedule k1,k2,k3;
	DES_cblock initVec;
#endif
public:
	CMAC();
	CMAC(const ByteArray &key, const ByteArray &iv);
	~CMAC(void);

	void Init(const ByteArray &key, const ByteArray &iv);
    ByteDynArray Mac(const ByteArray &data);
};
