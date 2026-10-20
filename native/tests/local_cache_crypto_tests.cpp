// SPDX-License-Identifier: BSD-3-Clause
#include "local_cache.h"
#include <iostream>
#include <stdexcept>
using namespace cie_cache;
int main(){try{
 Bytes key(64);for(size_t i=0;i<key.size();++i)key[i]=(uint8_t)i;
 const char* hex="4349454341434803000102030405060708090a0b0c0d0e0f5ad9114e7e67bfd7592a7e2cecd7f18fd81cd8c23f6ae61748ca6e6c569429947f207e2b082965acfd4511fc42003591";
 Bytes golden;for(size_t i=0;hex[i];i+=2){auto n=[](char c){return c<='9'?c-'0':c-'a'+10;};golden.push_back(uint8_t(n(hex[i])*16+n(hex[i+1])));}
 Bytes plain{1,'1','2','3','4',0,3,1,2,3};
 if(decrypt(key,"cie-cache-known-answer",golden)!=plain)return 1;
 auto a=encrypt(key,"TEST/card/A",plain),b=encrypt(key,"TEST/card/A",plain);
 if(a==b||decrypt(key,"TEST/card/A",a)!=plain)return 2;
 for(size_t i=0;i<a.size();++i){a[i]^=1;bool rejected=false;try{(void)decrypt(key,"TEST/card/A",a);}catch(...){rejected=true;}a[i]^=1;if(!rejected)return 3;}
 for(const auto& binding:{"TEST/card/B","TEST/web/A","OTHER/card/A"}){bool rejected=false;try{(void)decrypt(key,binding,a);}catch(...){rejected=true;}if(!rejected)return 4;}
 for(size_t i=0;i<key.size();++i){key[i]^=1;bool rejected=false;try{(void)decrypt(key,"TEST/card/A",a);}catch(...){rejected=true;}key[i]^=1;if(!rejected)return 5;}
 std::cout<<"{\"passed\":true,\"crossPlatformKnownAnswer\":true,\"tamperingRejected\":true,\"bindingAndWrongKeyRejected\":true,\"randomIv\":true}\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 6;}}
