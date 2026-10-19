// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <stdint.h>
// Separate from current certificate validation. No pointers/platform-sized fields.
enum CieTimestampStatus { CIE_TS_NOT_CHECKED=0, CIE_TS_ABSENT=1, CIE_TS_VERIFIED=2,
    CIE_TS_INVALID=3, CIE_TS_INDETERMINATE=4 };
enum CieHistoricalStatus { CIE_HISTORY_INDETERMINATE=0, CIE_HISTORY_VALID=1, CIE_HISTORY_INVALID=2 };
typedef struct CIE_TEMPORAL_VALIDATION {
    uint32_t size, timestampStatus, historicalStatus, timestampCount;
    int64_t referenceTime; // UTC epoch seconds, only a verified token can set it.
    int32_t tsaRevocationStatus, signerRevocationStatus;
    char timestampReason[96], historicalReason[96], utcTime[32], policy[96];
} CIE_TEMPORAL_VALIDATION;
