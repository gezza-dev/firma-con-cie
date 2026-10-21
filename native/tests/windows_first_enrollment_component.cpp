// SPDX-License-Identifier: BSD-3-Clause
// Metadata-only fake, no minidriver entry points or private operations.
#include <windows.h>
extern "C" __declspec(dllexport) DWORD CiePairingStorageVersion(){return 3;}
