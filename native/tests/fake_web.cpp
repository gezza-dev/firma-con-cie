// SPDX-License-Identifier: BSD-3-Clause
// Isolated OS-provider tests only. Never copied to a production runtime.
#include "cie_web.h"
#include "web_policy.h"
#include <cstring>
#include "fixtures/web_certificate.h"
struct CieWebSession {bool authenticated=false,attempted=false;unsigned selection=0;};
static unsigned signs=0,auths=0,selection=0;
static uint8_t lastSignInput[83]{};
static uint32_t lastSignInputSize=0;
extern "C" {
uint32_t cie_web_abi_version(){return 1;}
int32_t cie_web_open(const uint8_t*,uint32_t,CieWebTransmit,void*,const char*,CieWebSession** p){if(!p)return -1;*p=new CieWebSession;(*p)->selection=++selection;return 0;}
void cie_web_close(CieWebSession* p){delete p;}
int32_t cie_web_identifier(CieWebSession*,char* out,uint32_t* size){const char id[]="TESTWEB0000001";if(!size||!out||*size<sizeof(id))return -1;memcpy(out,id,sizeof(id));*size=sizeof(id);return 0;}
int32_t cie_web_certificate(CieWebSession*,uint8_t* out,uint32_t* size){if(!size)return -1;auto capacity=*size;*size=sizeof(testCertificate);if(out){if(capacity<sizeof(testCertificate))return -6;memcpy(out,testCertificate,sizeof(testCertificate));}return 0;}
int32_t cie_web_set_certificate(CieWebSession*,const uint8_t*,uint32_t){return 0;}
int32_t cie_web_authenticate(CieWebSession* p,char* pin,uint32_t size){
 ++auths;if(!p||!pin||size!=8)return -1;
 bool ok=!memcmp(pin,"12345678",8);cie_web::wipe(pin,size);
 // Another context's discovery/reset invalidates local IAS selection/SM.
 if(p->selection!=selection)return CIE_WEB_CARD;
 if(p->attempted)return -5;p->attempted=true;p->authenticated=ok;return ok?0:0x63c2;
}
int32_t cie_web_sign(CieWebSession* p,const uint8_t* data,uint32_t length,uint8_t* out,uint32_t* size){
 if(!p||!cie_web::digestInfo(data,length))return -7;if(!p->authenticated)return -4;
 if(!out||*size<256){*size=256;return out?-6:0;}++signs;
 memcpy(lastSignInput,data,length);lastSignInputSize=length;
 for(unsigned i=0;i<256;++i)out[i]=i;*size=256;return 0;
}
CIE_WEB_API unsigned cie_web_fake_signs(){return signs;}
CIE_WEB_API unsigned cie_web_fake_auths(){return auths;}
CIE_WEB_API uint32_t cie_web_fake_sign_input(uint8_t* out,uint32_t capacity){
 if(out&&capacity>=lastSignInputSize)memcpy(out,lastSignInput,lastSignInputSize);
 return lastSignInputSize;
}
}
