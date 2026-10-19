// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <memory.h>
#include <stdio.h>
#include <errno.h>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <winscard.h>
#include <io.h>
#include "../../platform/pcsc_utf8.h"
#undef SCardConnect
#undef SCardListReaders
#undef SCardGetStatusChange
#define SCardConnect cie_pcsc::connect
#define SCardListReaders cie_pcsc::list
#define SCardGetStatusChange cie_pcsc::change
#define STRICMP _stricmp
#else
#include <PCSC/wintypes.h>
#ifdef __APPLE__
#include <PCSC/winscard.h>
#else
#include <PCSC/winscard.h>
#endif
#include <strings.h>
#define STRICMP strcasecmp
typedef void* HANDLE;
typedef unsigned int UINT;
typedef unsigned short WORD;
typedef unsigned long HRESULT;
typedef char* PCHAR;
#define VOID void
#ifndef MAX_PATH
#define MAX_PATH 1024
#endif
#ifndef S_OK
#define S_OK 0
#endif
#ifndef LOWORD
#define LOWORD(l) ((l) & 0xffff)
#define HIWORD(l) (((l) >> 16) & 0xffff)
#endif
#ifndef LOBYTE
#define LOBYTE(l) ((uint8_t)((l) & 0xff))
#define HIBYTE(l) ((uint8_t)(((l) >> 8) & 0xff))
#endif
#ifndef MAKEWORD
#define MAKEWORD(lo,hi) ((lo) + ((hi) * 256))
#endif
#ifndef ERROR_FILE_NOT_FOUND
#define ERROR_FILE_NOT_FOUND 2
#define ERROR_MORE_DATA 234
#define ERROR_INVALID_DATA 13
#define ERROR_INVALID_HANDLE 6
#define ERROR_SUCCESS 0
#endif
inline unsigned long GetLastError() { return errno; }
inline void SetLastError(unsigned long value) { errno = (int)value; }
#endif
#ifndef IN
#define IN
#define OUT
#endif
#define NNULL 0
#define BT0_PADDING 0
#define BT1_PADDING 1
#define BT2_PADDING 2
#ifndef CALG_MD2
#define CALG_MD2 1
#define CALG_MD5 2
#define CALG_SHA1 3
#endif
#define ERROR_UNABLE_TO_ALLOCATE 226
#define ODS(...) ((void)0) // Raw legacy diagnostics stay disabled, without evaluating arguments.
int atox(const char* value);
