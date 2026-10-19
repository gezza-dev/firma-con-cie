#pragma once
#ifdef CIE_LEGACY_WINDOWS
#include <winscard.h>
#else
#include "cie_platform.h"
#endif
#include "Token.h"
#include "../Util/SyncroMutex.h"

class CCardLocker
{
	SCARDHANDLE hCard;
public:
	CCardLocker(SCARDHANDLE card);
	~CCardLocker(void);
	void Lock();
	void Unlock();
};
