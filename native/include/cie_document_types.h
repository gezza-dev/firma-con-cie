// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <stdint.h>
// Reserved appearance mode: text comes from the live signing CIE certificate.
#define CIE_PDF_CARDHOLDER_NAME "cie:cardholder-name-v1"
typedef struct CiePdfPageInfo {
    uint32_t size;
    int32_t pageCount;
    int32_t rotation;
    int32_t reserved;
    double width, height;
} CiePdfPageInfo;
// Rectangle in the displayed CropBox: normalized top-left origin, zero-based page.
typedef struct CiePdfAppearance {
    uint32_t size;
    int32_t page;
    double left, top, width, height;
    const char* imagePath;
} CiePdfAppearance;
