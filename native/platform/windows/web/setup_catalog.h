// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <windows.h>
#include "setup_policy.h"
#include <map>
#include <cstring>
namespace cie_setup {
struct Value {
 unsigned type=0;std::vector<uint8_t> bytes;
 bool operator==(const Value& b)const{return type==b.type&&bytes==b.bytes;}
};
using Values=std::map<std::wstring,Value>;
using Database=std::map<std::wstring,Values>;
template<class Map>auto findValue(Map& values,const wchar_t* key){return std::find_if(values.begin(),values.end(),[&](const auto& v){return CompareStringOrdinal(v.first.c_str(),-1,key,-1,TRUE)==CSTR_EQUAL;});}
inline void put(Values& values,const wchar_t* key,Value value){auto p=findValue(values,key);if(p==values.end())values[key]=std::move(value);else p->second=std::move(value);}
inline Value binary(const std::vector<uint8_t>& b){return {3,b};} // REG_BINARY
inline Value text(const std::wstring& s){Value v{1,{}};v.bytes.resize((s.size()+1)*sizeof(wchar_t));std::memcpy(v.bytes.data(),s.c_str(),v.bytes.size());return v;}
inline std::wstring stringValue(const Values& values,const wchar_t* key){
 auto p=findValue(values,key);if(p==values.end()||p->second.type!=1||p->second.bytes.empty()||p->second.bytes.size()%sizeof(wchar_t))return {};
 std::wstring result(p->second.bytes.size()/sizeof(wchar_t),0);std::memcpy(result.data(),p->second.bytes.data(),p->second.bytes.size());
 if(result.back()!=0)return {};result.pop_back();if(result.find(L'\0')!=std::wstring::npos)return {};return result;
}
inline bool pattern(const Values& values,std::vector<uint8_t>& atr,std::vector<uint8_t>& mask){
 auto a=findValue(values,L"ATR"),m=findValue(values,L"ATRMask");
 if(a==values.end()||a->second.type!=3||a->second.bytes.empty()||a->second.bytes.size()>36)return false;
 atr=a->second.bytes;
 // An incomplete foreign mask is treated conservatively as matching all bytes
 // of this ATR length, never as permission to overwrite that registration.
 mask=m!=values.end()&&m->second.type==3&&m->second.bytes.size()==atr.size()?m->second.bytes:std::vector<uint8_t>(atr.size(),0);
 return true;
}
inline bool overlaps(const std::vector<uint8_t>& a,const std::vector<uint8_t>& ma,const std::vector<uint8_t>& b,const std::vector<uint8_t>& mb){
 if(a.size()!=b.size())return false;
 for(size_t i=0;i<a.size();++i)if((a[i]^b[i])&ma[i]&mb[i])return false;return true;
}
inline bool subset(const std::vector<uint8_t>& a,const std::vector<uint8_t>& ma,const CardPattern& b){
 if(a.size()!=b.atr.size())return false;
 for(size_t i=0;i<a.size();++i)if((ma[i]&b.mask[i])!=b.mask[i]||((a[i]^b.atr[i])&b.mask[i]))return false;return true;
}
struct CatalogPlan {int code=0;Database before,after;};
template<class OwnsModule>
CatalogPlan planCatalog(const Database& all,const std::wstring& module,OwnsModule ownsModule){
 CatalogPlan plan;plan.before=all;auto& after=plan.after;
 for(const auto& item:all)if(ownedName(item.first)){
  const auto& v=item.second;std::vector<uint8_t> atr,mask;
  auto m=findValue(v,L"ATRMask");
  if(!pattern(v,atr,mask)||m==v.end()||m->second.type!=3||m->second.bytes.size()!=atr.size()||
     !ownsModule(stringValue(v,L"80000001"))||stringValue(v,L"Crypto Provider")!=L"Microsoft Base Smart Card Crypto Provider"||
     stringValue(v,L"Smart Card Key Storage Provider")!=L"Microsoft Smart Card Key Storage Provider"){
   plan.code=conflict;return plan;
  }
  after[item.first]=v;put(after[item.first],L"80000001",text(module));
 }
 for(const auto& card:cardCatalog){
  // Existing exact-ATR names are retained, including the name already used by
  // this PC. Multiple old exact NXP registrations become one official mask.
  std::vector<std::wstring> matches;
  for(const auto& item:after){std::vector<uint8_t> a,m;pattern(item.second,a,m);
   if(overlaps(a,m,card.atr,card.mask)){if(!subset(a,m,card)){plan.code=conflict;return plan;}matches.push_back(item.first);}}
  const std::wstring name=matches.empty()?std::wstring(cardName)+L" "+card.id:matches.front();
  if(matches.empty())for(const auto& existing:all)if(CompareStringOrdinal(existing.first.c_str(),-1,name.c_str(),-1,TRUE)==CSTR_EQUAL){plan.code=conflict;return plan;}
  for(size_t i=1;i<matches.size();++i)after.erase(matches[i]);
  auto& v=after[name];put(v,L"ATR",binary(card.atr));put(v,L"ATRMask",binary(card.mask));
  put(v,L"Crypto Provider",text(L"Microsoft Base Smart Card Crypto Provider"));
  put(v,L"Smart Card Key Storage Provider",text(L"Microsoft Smart Card Key Storage Provider"));put(v,L"80000001",text(module));
 }
 for(const auto& item:all)if(!ownedName(item.first)){
  std::vector<uint8_t> a,m;if(!pattern(item.second,a,m))continue;
  for(const auto& own:after){std::vector<uint8_t> b,n;pattern(own.second,b,n);if(overlaps(a,m,b,n)){plan.code=conflict;return plan;}}
 }
 return plan;
}
// Store supplies read/write/erase for only its fixed database. All previous
// raw values are restored after failure; no user profile or card is involved.
template<class Store>
int applyCatalog(Store& store,const CatalogPlan& plan){
 if(plan.code)return plan.code;
 if(store.read()!=plan.before)return conflict;
 std::vector<std::wstring> touched;
 auto rollback=[&]{bool restored=true;for(auto it=touched.rbegin();it!=touched.rend();++it){auto p=plan.before.find(*it);
  if(p==plan.before.end()){if(!store.erase(*it))restored=false;}else if(!store.write(*it,p->second))restored=false;}
  return restored?registrationFailure:recoveryRequired;};
 for(const auto& item:plan.after){auto p=plan.before.find(item.first);if(p!=plan.before.end()&&p->second==item.second)continue;
  touched.push_back(item.first);if(!store.write(item.first,item.second))return rollback();}
 for(const auto& item:plan.before)if(ownedName(item.first)&&!plan.after.count(item.first)){
  touched.push_back(item.first);if(!store.erase(item.first))return rollback();}
 Database expected=plan.before;for(auto it=expected.begin();it!=expected.end();)if(ownedName(it->first))it=expected.erase(it);else ++it;
 expected.insert(plan.after.begin(),plan.after.end());
 try{if(store.read()!=expected)return rollback();}catch(...){return rollback();}return installed;
}
}
