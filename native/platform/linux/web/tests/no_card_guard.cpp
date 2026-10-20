// SPDX-License-Identifier: BSD-3-Clause
// Preload guard for the production-module metadata test. No hardware calls can
// escape through context establishment or connection, even on a developer PC.
#include <winscard.h>
#include <atomic>
static std::atomic<unsigned> calls{0};
extern "C" {
__attribute__((visibility("default"))) unsigned CieNoCardCalls(){return calls.load();}
__attribute__((visibility("default"))) LONG SCardEstablishContext(DWORD,LPCVOID,LPCVOID,LPSCARDCONTEXT out){++calls;if(out)*out=0;return SCARD_E_NO_SERVICE;}
__attribute__((visibility("default"))) LONG SCardConnect(SCARDCONTEXT,LPCSTR,DWORD,DWORD,LPSCARDHANDLE,LPDWORD){++calls;return SCARD_E_NO_SERVICE;}
}
