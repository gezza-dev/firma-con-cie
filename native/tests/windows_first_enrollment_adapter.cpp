// SPDX-License-Identifier: BSD-3-Clause
// Synthetic authentication/SOD result, with a valid public certificate for the
// real WinCrypt publication code. No smart-card implementation is linked.
#include <windows.h>
#include "windows_public_certificate_fixture.h"
#define cie_card_enroll_v2 original_fake_enroll_v2
#include "fake_card_adapter.cpp"
#undef cie_card_enroll_v2
extern "C" CIE_EXPORT int64_t cie_card_enroll_v2(const char* r,const char* id,char* pin,CieEnrollmentMaterial* m){
 auto status=original_fake_enroll_v2(r,id,pin,m);if(status)return status;
 static_assert(sizeof(testCertificate)<=sizeof(m->certificate));
 m->certificateLength=sizeof(testCertificate);std::memcpy(m->certificate,testCertificate,sizeof(testCertificate));return 0;
}
