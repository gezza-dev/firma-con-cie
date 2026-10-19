// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <stdint.h>
// Additive v2 enrollment capability. Public SOD-verified data only.
// The caller initializes size; no PIN fragments are returned through this ABI.
struct CieEnrollmentMaterial {
 uint32_t size, version, certificateLength;
 uint8_t certificate[8192];
 char fullName[512];
};
