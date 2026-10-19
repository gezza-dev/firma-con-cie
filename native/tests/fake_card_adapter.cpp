// SPDX-License-Identifier: BSD-3-Clause
// Synthetic signer, explicitly separated from real card tests.
#include "cie_bridge.h"
#include "cie_enrollment_types.h"
#include <cstring>
#include <fstream>
#ifdef __APPLE__
#include <sys/stat.h>
#include <sys/xattr.h>
#endif
static int attempts = 0;
static int pinAttempts=0;
extern "C" CIE_EXPORT int fake_pin_attempts() { return pinAttempts; }
static int64_t update(const char* expected,char* authentication,char* replacement,int* phase) {
    *phase=0;
    if(std::strcmp(expected,"TEST")) return -10;
    *phase=1;pinAttempts++;
    if(!std::strcmp(authentication,"99999999")) return 0x6983;
    if(std::strcmp(authentication,"10293847")) return 0x63C2;
    *phase=2;
    if(!std::strcmp(replacement,"97531086")) return -2;
    *phase=3;return 0;
}
extern "C" CIE_EXPORT int64_t cie_card_change_pin(const char*,const char* expected,char* current,char* replacement,int* phase) {
    return update(expected,current,replacement,phase);
}
extern "C" CIE_EXPORT int64_t cie_card_unblock_pin(const char*,const char* expected,char* puk,char* replacement,int* phase) {
    return update(expected,puk,replacement,phase);
}
extern "C" CIE_EXPORT int fake_attempts() { return attempts; }
extern "C" CIE_EXPORT int cie_card_identify(const char*, char* card, size_t capacity) {
    if (capacity < 5) return -1;
    std::strcpy(card, "TEST"); return 0;
}
extern "C" CIE_EXPORT int64_t cie_card_sign(const char*, const char* expected, const char*,
    const char* output, const char*, char* pin) {
    if (std::strcmp(expected, "TEST")) return -10;
    attempts++;
    if (std::strcmp(pin, "12345678")) return 0x63C2;
    {std::ofstream file(output);file << "Synthetic signed output, not a real signature\n";}
#ifdef __APPLE__
    chflags(output,UF_HIDDEN|UF_NODUMP);
    unsigned char finder[32]{};finder[8]=0x40;finder[9]=1;setxattr(output,"com.apple.FinderInfo",finder,sizeof(finder),0,0);
#endif
    return 0;
}

static int appearancePage=-1;
extern "C" CIE_EXPORT int fake_appearance_page(){return appearancePage;}
extern "C" CIE_EXPORT int64_t cie_card_sign_pdf(const char* r,const char* c,const char* i,const char* o,char* p,const CiePdfAppearance* a) {
    if(!a)return -20;appearancePage=a->page;return cie_card_sign(r,c,i,o,"pdf",p);
}

static int pairAttempts=0;
extern "C" CIE_EXPORT int fake_pair_attempts(){return pairAttempts;}
extern "C" CIE_EXPORT int64_t cie_card_pair_authenticate(const char*,const char* id,char* pin){
 if(std::strcmp(id,"TEST"))return -10;
 if(!std::strcmp(pin,"88888888"))return -37;
 ++pairAttempts;
 if(!std::strcmp(pin,"77777777"))return -44;
 auto code=!std::strcmp(pin,"12345678")?0:!std::strcmp(pin,"99999999")?0x6983:0x63c2;
 volatile char* p=pin;for(int i=0;i<8;++i)p[i]=0;return code;
}
static int webAttempts=0;
extern "C" CIE_EXPORT int fake_web_attempts(){return webAttempts;}
extern "C" CIE_EXPORT int64_t cie_card_web_enroll(const char*,const char* id,char* pin,uint8_t* output,uint32_t* size){
 if(!size||*size<8192||!output)return -1;if(std::strcmp(id,"TEST"))return -10;
 ++webAttempts;auto status=!std::strcmp(pin,"12345678")?0:!std::strcmp(pin,"99999999")?0x6983:0x63c2;
 volatile char* p=pin;for(int i=0;i<8;++i)p[i]=0;
 if(status)return status;output[0]=0x30;output[1]=1;output[2]=0;*size=3;return 0;
}

static int enrollmentAttempts=0;
extern "C" CIE_EXPORT int fake_enrollment_attempts(){return enrollmentAttempts;}
extern "C" CIE_EXPORT int cie_card_identify_idle(const char* r,char* c,size_t n){return cie_card_identify(r,c,n);}
extern "C" CIE_EXPORT int64_t cie_card_enroll_v2(const char*,const char* id,char* pin,CieEnrollmentMaterial* material){
 if(!material||material->size!=sizeof(*material)||std::strcmp(id,"TEST"))return -10;
 ++enrollmentAttempts;auto status=!std::strcmp(pin,"12345678")?0:!std::strcmp(pin,"99999999")?0x6983:0x63c2;
 for(int i=0;i<8;++i)pin[i]=0;if(status)return status;
 material->version=2;material->certificateLength=3;material->certificate[0]=0x30;material->certificate[1]=1;material->certificate[2]=0;std::strcpy(material->fullName,"Nome Cognome");return 0;
}
