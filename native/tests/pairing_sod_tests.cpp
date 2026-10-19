// SPDX-License-Identifier: BSD-3-Clause
#include "pairing_sod.h"
#include <vector>
#include <iostream>
using V=std::vector<uint8_t>;
V cat(V a,const V& b){a.insert(a.end(),b.begin(),b.end());return a;}
V tlv(uint8_t tag,const V& v){V out{tag};if(v.size()<128)out.push_back(v.size());else{out.push_back(0x81);out.push_back(v.size());}return cat(out,v);}
V integer(uint8_t v){return tlv(2,V{v});}
V group(uint8_t id,uint8_t hash){return tlv(0x30,cat(integer(id),tlv(4,V{hash})));}
V sod(const V& groups){auto data=tlv(0x30,cat(cat(integer(0),integer(0)),tlv(0x30,groups)));auto encap=tlv(0x30,cat(tlv(6,V{1}),tlv(0xa0,tlv(4,data))));auto cms=tlv(0x30,cat(cat(integer(0),tlv(0x31,{})),encap));return tlv(0x77,tlv(0x30,cat(tlv(6,V{1}),tlv(0xa0,cms))));}
int main(){int checks=0;std::map<uint8_t,ByteDynArray> hashes;
 for(auto id:{0xa1,0xa2,0xa3,0xa4,0xa5,0x1b}){uint8_t b=uint8_t(id);hashes[b]=ByteArray(&b,1);}
 auto accepts=[&](V raw){ByteArray input(raw.data(),raw.size());try{cie_pairing::checkSodDigests(input,hashes);return true;}catch(...){return false;}};
 V valid;for(auto& entry:hashes)valid=cat(valid,group(entry.first,entry.first));
 auto check=[&](bool v){if(!v)throw std::runtime_error("SOD strict boundary failure");++checks;};
 try{
 check(accepts(sod(valid)));check(!accepts(sod({})));check(!accepts(sod(cat(valid,group(0xa1,0xa1)))));
 V missing;for(auto& entry:hashes)if(entry.first!=0xa3)missing=cat(missing,group(entry.first,entry.first));check(!accepts(sod(missing)));
 V altered;for(auto& entry:hashes)altered=cat(altered,group(entry.first,entry.first==0xa3?0:entry.first));check(!accepts(sod(altered)));
 check(!accepts(sod(cat(valid,group(0xff,0xff)))));check(!accepts(V{0x77,0}));
 std::cout<<"{\"passed\":true,\"sodStrictChecks\":"<<checks<<"}\n";return 0;
 }catch(...){return 1;}
}
