// SPDX-License-Identifier: BSD-3-Clause
// Used only by the browser setup subprocess, never by the browser itself.
// Registering a module must not establish a smart-card connection.
#include <winscard.h>
extern "C" {
__attribute__((visibility("default"))) LONG SCardEstablishContext(
    DWORD, LPCVOID, LPCVOID, LPSCARDCONTEXT context) {
  if (context) *context = 0;
  return SCARD_E_NO_SERVICE;
}
__attribute__((visibility("default"))) LONG SCardConnect(
    SCARDCONTEXT, LPCSTR, DWORD, DWORD, LPSCARDHANDLE, LPDWORD) {
  return SCARD_E_NO_SERVICE;
}
}
