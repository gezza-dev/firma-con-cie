// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstdint>
#include <cstring>
namespace cie_web {
inline bool digestInfo(const uint8_t* bytes,uint32_t size) {
 // Canonical DER AlgorithmIdentifier including NULL. Reject BER, arbitrary raw
 // RSA blocks, SHA-1 and malformed/trailing data before calling the card.
 static const uint8_t prefix[]={0x30,0,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,0,0x05,0x00,0x04,0};
 if(!bytes||size<19)return false;
 uint32_t digest=bytes[14]==1?32:bytes[14]==2?48:bytes[14]==3?64:0;
 if(!digest||size!=19+digest||bytes[1]!=size-2||bytes[18]!=digest)return false;
 for(unsigned i=0;i<19;++i)if(i!=1&&i!=14&&i!=18&&bytes[i]!=prefix[i])return false;
 return true;
}
inline void wipe(char* bytes,uint32_t size){if(bytes){volatile char* p=bytes;while(size--)*p++=0;}}
struct State {
 bool failed=false,attempted=false,authenticated=false;
 bool beginAuthentication(){if(failed||attempted)return false;attempted=true;return true;}
 void fail(){failed=true;authenticated=false;}
};
}
