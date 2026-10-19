// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstddef>
#include <cstdint>
#include "cie_document_types.h"
#include "../backend/cie_sign_sdk/include/CertificateValidation.h"
#include "../backend/cie_sign_sdk/include/TemporalValidation.h"
static_assert(sizeof(CIE_TEMPORAL_VALIDATION) == 352);
using DocumentTemporalFn = unsigned long (*)(CIE_TEMPORAL_VALIDATION*);
using TemporalFn = unsigned long (*)(int, CIE_TEMPORAL_VALIDATION*);
static_assert(sizeof(CIE_CERTIFICATE_VALIDATION) == 184);
using ValidationFn = unsigned long (*)(int, CIE_CERTIFICATE_VALIDATION*);
// Matches cie-pkcs11/Sign/CIEVerify.h in the pinned v1.5.2 backend.
// The optional native card adapter checks this layout against the original header.
struct CieVerifyInfo {
    char name[512], surname[512], cn[512], signingTime[512], cadn[512];
    int CertRevocStatus;
    bool isSignValid, isCertValid;
};
static_assert(offsetof(CieVerifyInfo, CertRevocStatus) == 2560);
static_assert(sizeof(CieVerifyInfo) == 2568);
using VerifyFn = unsigned long (*)(const char*, const char*, int, const char*);
using InfoFn = unsigned long (*)(int, CieVerifyInfo*);
using CountFn = unsigned long (*)();
// The companion adapter is compiled with the SAME C++ headers/toolchain ABI as
// the original middleware. Only its plain C interface is visible to this bridge.
using IdentifyFn = int (*)(const char*, char*, size_t);
using SignFn = int64_t (*)(const char*, const char*, const char*, const char*, const char*, char*);
using PinFn = int64_t (*)(const char*, const char*, char*, char*, int*);
using ExtractFn = unsigned long (*)(const char*,const char*);
using PdfInfoFn = int (*)(const char*,int,CiePdfPageInfo*);
using PdfPrepareFn = int (*)(const char*,const CiePdfAppearance*,CiePdfAppearance*);
using PdfSignFn = int64_t (*)(const char*,const char*,const char*,const char*,char*,const CiePdfAppearance*);

using P7mInfoFn=int (*)(const char*,uint32_t*);
using P7mPreservedFn=int (*)(const char*,const char*);

#include "cie_network_types.h"
using NetworkProbeFn=int (*)(const CieNetworkOptions*,CieNetworkProbe*);
