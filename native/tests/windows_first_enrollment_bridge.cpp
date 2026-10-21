// SPDX-License-Identifier: BSD-3-Clause
// Compile the production ABI with reader access explicitly disabled. Only the
// synthetic adapter may authenticate; this test DLL is never distributed.
#include <windows.h>
#include <winscard.h>
static unsigned readerAttempts=0;
static LONG noReaderContext(DWORD,LPCVOID,LPCVOID,LPSCARDCONTEXT){++readerAttempts;return SCARD_E_NO_SERVICE;}
#define SCardEstablishContext noReaderContext
#undef NOMINMAX // cie_bridge.cpp defines it before its own Windows includes.
#include "../src/cie_bridge.cpp"
extern "C" CIE_EXPORT unsigned test_reader_attempts(){return readerAttempts;}
