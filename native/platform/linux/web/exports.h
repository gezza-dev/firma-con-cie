// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#ifdef _WIN32
#define CIE_PKCS11_EXPORT __declspec(dllexport)
#else
#define CIE_PKCS11_EXPORT __attribute__((visibility("default")))
#endif
