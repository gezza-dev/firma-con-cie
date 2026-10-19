// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "cie-pkcs11/Util/Array.h"
#include "cie-pkcs11/Crypto/ASNParser.h"
#include <map>
#include <set>
#include <stdexcept>
namespace cie_pairing {
// Additional strict DG checks: the legacy SHA-256 verifier only prints some
// mismatches. Signature verification still runs separately in IAS.
inline std::map<uint8_t,ByteDynArray> sodDigests(ByteArray& sod){
 CASNParser parser;parser.Parse(sod);
 auto& cms=parser.tags.at(0)->Child(0,0x30).Child(1,0xa0).Child(0,0x30);
 auto encoded=cms.Child(2,0x30).Child(1,0xa0).Child(0,0x04).content;
 CASNParser inner;inner.Parse(encoded);
 auto& groups=inner.tags.at(0)->CheckTag(0x30).Child(2,0x30);
 std::map<uint8_t,ByteDynArray> values;
 for(auto& entry:groups.tags){auto& item=entry->CheckTag(0x30);auto& number=item.Child(0,0x02).content;
  if(number.size()<1||number.size()>2||(number.size()==2&&number[0]!=0))throw std::runtime_error("SOD invalid DG");
  auto id=number[number.size()-1];auto& digest=item.Child(1,0x04).content;
  if(!values.emplace(id,digest).second)throw std::runtime_error("SOD duplicate DG");
 }
 return values;
}
inline void checkSodDigests(ByteArray& sod,const std::map<uint8_t,ByteDynArray>& expected){
 auto values=sodDigests(sod);if(values.size()!=expected.size())throw std::runtime_error("SOD missing DG");
 for(auto& entry:expected){auto found=values.find(entry.first);if(found==values.end()||!entry.second.size()||found->second!=entry.second)throw std::runtime_error("SOD DG mismatch");}
}
}
