// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <stdint.h>

enum CieTrustStatus {
    CIE_TRUST_NOT_CHECKED = 0, CIE_TRUST_TRUSTED = 1,
    CIE_TRUST_UNTRUSTED = 2, CIE_TRUST_INVALID = 3, CIE_TRUST_UNKNOWN = 4
};
// Additive, size-checked C ABI. No pointers or platform-sized integer fields.
typedef struct CIE_CERTIFICATE_VALIDATION {
    uint32_t size;
    uint32_t status;
    int32_t error;
    uint32_t chainLength;
    int32_t revocationStatus; // Whole chain excluding the root; SDK revocation enum.
    int32_t revocationType;   // Leaf: OCSP=1, CRL=2, unavailable=0.
    char trustSource[32];
    char reason[64];
    char revocationReason[64];
} CIE_CERTIFICATE_VALIDATION;
