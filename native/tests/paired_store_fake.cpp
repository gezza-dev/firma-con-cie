// SPDX-License-Identifier: BSD-3-Clause
// Only linked into cie_bridge_pairing_tests, never production runtime.
#include "paired_store.h"
#include "cie_bridge.h"
#include <map>
#include <cstring>
namespace {std::map<std::string,std::string> records;std::map<std::string,std::vector<uint8_t>> publicRecords;bool fail=false;bool failErase=false;int failPhase=0;int eraseCalls=0;}
extern "C" CIE_EXPORT void fake_store_fail(int v){fail=v!=0;}
extern "C" CIE_EXPORT void fake_enrollment_store_fail(int phase){failPhase=phase;}
extern "C" CIE_EXPORT void fake_store_erase_fail(int v){failErase=v!=0;}
extern "C" CIE_EXPORT int fake_store_erase_calls(){return eraseCalls;}
namespace cie_pairing {
bool supported(){return true;}
void check(){if(fail)throw std::runtime_error("locked");}
void prepare(){check();}
bool read(const std::string& id,Secret& out){checkId(id);if(invalidated(id))return false;check();auto i=records.find(id);if(i==records.end())return false;std::memcpy(out.bytes.data(),i->second.data(),4);return true;}
void write(const std::string& id,const char* p){check();checkId(id);if(failPhase==2)throw std::runtime_error("locked");records[id]=p;}
void erase(const std::string& id){++eraseCalls;check();checkId(id);if(failErase)throw StoreError(-25308);records.erase(id);}
std::vector<uint8_t> readPublic(const std::string& id){check();checkId(id);auto it=publicRecords.find(id);return it==publicRecords.end()?std::vector<uint8_t>{}:it->second;}
void writePublic(const std::string& id,const std::vector<uint8_t>& bytes){check();checkId(id);if(failPhase==1)throw std::runtime_error("locked");publicRecords[id]=bytes;}
void erasePublic(const std::string& id){check();checkId(id);if(failPhase==3)throw StoreError(-25308);publicRecords.erase(id);}
void eraseForRemoval(const std::string& id,bool publicData){if(publicData)erasePublic(id);else erase(id);}
void eraseRecord(const std::string& id){erasePublic(id);erase(id);}
std::vector<std::string> listPublic(){check();std::vector<std::string> ids;for(auto& item:publicRecords)ids.push_back(item.first);return ids;}
std::vector<std::string> list(){check();std::vector<std::string> out;for(auto& i:records)if(!invalidated(i.first))out.push_back(i.first);return out;}
}
