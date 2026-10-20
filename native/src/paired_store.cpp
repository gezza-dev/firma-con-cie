// SPDX-License-Identifier: BSD-3-Clause
#include "paired_store.h"
#include "local_cache.h"
#include <cstring>
namespace cie_pairing {
namespace {
struct Record {Secret prefix;bool paired=false;std::vector<uint8_t> publicData;};
void checkPrefix(const char* p){if(!p||std::strlen(p)!=4||!std::all_of(p,p+4,[](char c){return c>='0'&&c<='9';}))throw std::runtime_error("pairing_invalid_record");}
void decode(const cie_cache::Bytes& bytes,Record& r){
 if(bytes.empty())return;
 if(bytes.size()<7||bytes[0]>1)throw std::runtime_error("pairing_cache_invalid");
 auto n=(size_t(bytes[5])<<8)|bytes[6];if(n>9000||bytes.size()!=7+n)throw std::runtime_error("pairing_cache_invalid");
 r.paired=bytes[0]!=0;if(r.paired){std::memcpy(r.prefix.bytes.data(),bytes.data()+1,4);checkPrefix(r.prefix.bytes.data());}
 else if(std::any_of(bytes.begin()+1,bytes.begin()+5,[](auto b){return b!=0;}))throw std::runtime_error("pairing_cache_invalid");
 r.publicData.assign(bytes.begin()+7,bytes.end());
}
cie_cache::Bytes encode(const Record& r){
 cie_cache::Bytes out(7+r.publicData.size(),0);out[0]=r.paired?1:0;if(r.paired)std::memcpy(out.data()+1,r.prefix.bytes.data(),4);
 out[5]=uint8_t(r.publicData.size()>>8);out[6]=uint8_t(r.publicData.size());std::copy(r.publicData.begin(),r.publicData.end(),out.begin()+7);return out;
}
void save(cie_cache::Store& store,const std::string& id,const Record& r){if(!r.paired&&r.publicData.empty())store.erase("card",id);else store.write("card",id,encode(r));}
}
bool supported(){return true;}
void prepare(){cie_cache::Store store(true);store.prepare();}
bool read(const std::string& id,Secret& out){checkId(id);if(invalidated(id))return false;cie_cache::Store store;Record r;decode(store.read("card",id),r);if(!r.paired)return false;std::memcpy(out.bytes.data(),r.prefix.bytes.data(),4);return true;}
void write(const std::string& id,const char* prefix){checkId(id);checkPrefix(prefix);cie_cache::Store store(true);Record r;decode(store.read("card",id),r);r.paired=true;std::memcpy(r.prefix.bytes.data(),prefix,4);save(store,id,r);}
std::vector<uint8_t> readPublic(const std::string& id){checkId(id);cie_cache::Store store;Record r;decode(store.read("card",id),r);return r.publicData;}
void writePublic(const std::string& id,const std::vector<uint8_t>& bytes){checkId(id);if(bytes.empty()||bytes.size()>9000)throw std::runtime_error("pairing_public_invalid");cie_cache::Store store(true);Record r;decode(store.read("card",id),r);r.publicData=bytes;save(store,id,r);}
void erase(const std::string& id){checkId(id);cie_cache::Store store;Record r;decode(store.read("card",id),r);r.paired=false;save(store,id,r);}
void erasePublic(const std::string& id){checkId(id);cie_cache::Store store;Record r;decode(store.read("card",id),r);r.publicData.clear();save(store,id,r);}
void eraseForRemoval(const std::string& id,bool publicData){if(publicData)erasePublic(id);else erase(id);}
void eraseRecord(const std::string& id){checkId(id);cie_cache::Store store;store.erase("card",id);}
std::vector<std::string> list(){cie_cache::Store store;std::vector<std::string> ids;
 for(const auto& id:store.list("card")){if(invalidated(id))continue;try{Record r;decode(store.read("card",id),r);if(r.paired)ids.push_back(id);}catch(const std::exception&){/* Corrupt entries remain removable via listPublic, never usable for PIN suffix signing. */}}
 return ids;
}
std::vector<std::string> listPublic(){cie_cache::Store store;std::vector<std::string> ids;
 for(const auto& id:store.list("card")){try{Record r;decode(store.read("card",id),r);if(!r.publicData.empty())ids.push_back(id);}catch(const std::exception&){ids.push_back(id);}}
 return ids;
}
}
