// SPDX-License-Identifier: BSD-3-Clause
#include "web_policy.h"
#include <vector>
#include <stdexcept>
#include <iostream>
static int checks=0;
static void check(bool b){++checks;if(!b)throw std::runtime_error("web policy regression");}
int main(){
 for(unsigned algorithm=1;algorithm<=3;++algorithm){
  uint8_t prefix[]={0x30,0,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,static_cast<uint8_t>(algorithm),0x05,0,0x04,0};
  auto n=algorithm==1?32:algorithm==2?48:64;prefix[1]=17+n;prefix[18]=n;
  std::vector<uint8_t> encoded(prefix,prefix+19);encoded.resize(19+n,0xaa);
  check(cie_web::digestInfo(encoded.data(),encoded.size()));
  check(!cie_web::digestInfo(encoded.data(),encoded.size()-1));
  encoded.push_back(0);check(!cie_web::digestInfo(encoded.data(),encoded.size()));encoded.pop_back();
  for(unsigned i=0;i<19;++i){auto old=encoded[i];encoded[i]^=0xff;check(!cie_web::digestInfo(encoded.data(),encoded.size()));encoded[i]=old;}
 }
 check(!cie_web::digestInfo(nullptr,51));
 cie_web::State state;check(state.beginAuthentication());check(!state.beginAuthentication());
 state.authenticated=true;state.fail();check(!state.authenticated);check(!state.beginAuthentication());
 char pin[]="12345678";cie_web::wipe(pin,8);for(unsigned i=0;i<8;++i)check(!pin[i]);
 std::cout<<checks<<" web policy checks passed\n";
}
