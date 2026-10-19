// SPDX-License-Identifier: BSD-3-Clause
#include "cie_web.h"
#include <iostream>
#include <stdexcept>
static int checks=0,calls=0;
static void check(bool b){++checks;if(!b)throw std::runtime_error("web ABI regression");}
static int32_t fail(void*,const uint8_t*,uint32_t,uint8_t*,uint32_t*){++calls;return -2;}
static int32_t oversized(void*,const uint8_t*,uint32_t,uint8_t*,uint32_t* size){++calls;++*size;return 0;}
int main(){
 check(cie_web_abi_version()==1);CieWebSession* result=reinterpret_cast<CieWebSession*>(1);
 check(cie_web_open(nullptr,0,fail,nullptr,nullptr,&result)==CIE_WEB_ARGUMENT);check(!result&&!calls);
 const uint8_t atr[]={0x3b,0x80,0x31,0x80,0x65,0x49,0x54,0x4e,0x58,0x50};
 check(cie_web_open(atr,sizeof(atr),fail,nullptr,"../invalid",&result)==CIE_WEB_ARGUMENT);check(!result&&!calls);
 check(cie_web_open(atr,sizeof(atr),fail,nullptr,nullptr,&result)==CIE_WEB_CARD);check(!result&&calls==1);
 calls=0;check(cie_web_open(atr,sizeof(atr),oversized,nullptr,nullptr,&result)==CIE_WEB_CARD);check(!result&&calls==1);
 uint32_t size=8;uint8_t buffer[8]{};char pin[]="12345678";
 check(cie_web_authenticate(nullptr,pin,8)==CIE_WEB_ARGUMENT);for(int i=0;i<8;++i)check(pin[i]==0);
 check(cie_web_sign(nullptr,buffer,8,buffer,&size)==CIE_WEB_ARGUMENT);
 check(cie_web_certificate(nullptr,buffer,&size)==CIE_WEB_ARGUMENT);cie_web_close(nullptr);
 std::cout<<checks<<" web ABI checks passed (no card/PIN)\n";
}
