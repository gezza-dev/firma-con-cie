// SPDX-License-Identifier: BSD-3-Clause
#include <windows.h>
#include <iostream>
#include <stdexcept>
#include "setup_registry.h"
using namespace cie_setup;
struct MemoryStore {
 Database state;int calls=0,fail=0;bool failRecovery=false,failRead=false;
 Database read(){if(failRead&&calls)throw int(registrationFailure);return state;}
 bool write(const std::wstring& name,const Values& v){if(++calls==fail||(failRecovery&&calls>fail))return false;state[name]=v;return true;}
 bool erase(const std::wstring& name){if(++calls==fail||(failRecovery&&calls>fail))return false;state.erase(name);return true;}
};
int main(){unsigned checks=0;auto check=[&](bool v){++checks;if(!v)throw std::runtime_error("catalog check "+std::to_string(checks));};
 try{
 auto owns=[](const auto& module){return module==L"old"||module==L"new";};
 const auto fresh=planCatalog({},L"new",owns);check(fresh.code==0&&fresh.after.size()==12);
 for(const auto& card:cardCatalog){
  auto name=std::wstring(cardName)+L" "+card.id;check(ownedName(name));
  check(fresh.after.at(name).at(L"ATR")==binary(card.atr));check(fresh.after.at(name).at(L"ATRMask")==binary(card.mask));
  check(stringValue(fresh.after.at(name),L"80000001")==L"new");
  for(size_t i=0;i<card.atr.size();++i){auto changed=card.atr;changed[i]^=0x01;
   check(overlaps(changed,std::vector<uint8_t>(changed.size(),0xff),card.atr,card.mask)==!(card.mask[i]&1));}
 }
 for(size_t i=0;i<cardCatalog.size();++i)for(size_t j=0;j<i;++j)
  check(!overlaps(cardCatalog[i].atr,cardCatalog[i].mask,cardCatalog[j].atr,cardCatalog[j].mask));
 MemoryStore empty;check(applyCatalog(empty,fresh)==0);check(empty.state==fresh.after);
 const auto stable=planCatalog(empty.state,L"new",owns);empty.calls=0;check(applyCatalog(empty,stable)==0&&empty.calls==0);
 for(int fail=1;fail<=12;++fail){MemoryStore store;store.fail=fail;check(applyCatalog(store,fresh)==registrationFailure);check(store.state.empty());}
 MemoryStore unrecovered;unrecovered.fail=2;unrecovered.failRecovery=true;check(applyCatalog(unrecovered,fresh)==recoveryRequired);
 MemoryStore unreadable;unreadable.failRead=true;check(applyCatalog(unreadable,fresh)==registrationFailure&&unreadable.state.empty());
 // Preserve an already working exact-ATR name and unrelated registry values.
 auto exact=fresh.after.at(std::wstring(cardName)+L" CIE_3");auto nxp=cardCatalog[2].atr;nxp.back()=0x55;
 exact[L"ATR"]=binary(nxp);exact[L"ATRMask"]=binary(std::vector<uint8_t>(nxp.size(),0xff));exact[L"80000001"]=text(L"old");exact[L"private annotation"]=text(L"retained");
 Database old{{cardName,exact}};auto upgraded=planCatalog(old,L"new",owns);
 check(upgraded.code==0&&upgraded.after.size()==12&&upgraded.after.count(cardName));
 check(upgraded.after.at(cardName).at(L"private annotation")==text(L"retained"));
 check(upgraded.after.at(cardName).at(L"ATRMask")==binary(cardCatalog[2].mask));
 auto alias=std::wstring(cardName)+L" 0123456789abcdef";old[alias]=exact;
 auto merged=planCatalog(old,L"new",owns);check(merged.code==0&&merged.after.size()==12&&!merged.after.count(alias));
 for(int fail=1;fail<=13;++fail){MemoryStore store;store.state=old;store.fail=fail;check(applyCatalog(store,merged)==registrationFailure);check(store.state==old);}
 MemoryStore upgradedStore;upgradedStore.state=old;check(applyCatalog(upgradedStore,merged)==0&&upgradedStore.state==merged.after);
 auto foreign=exact;foreign[L"80000001"]=text(L"foreign.dll");
 check(planCatalog({{L"Official CIE Middleware",foreign}},L"new",owns).code==conflict);
 auto lower=foreign;lower[L"atr"]=lower.at(L"ATR");lower.erase(L"ATR");lower[L"atrmask"]=lower.at(L"ATRMask");lower.erase(L"ATRMask");
 check(planCatalog({{L"Official lowercase values",lower}},L"new",owns).code==conflict);
 lower[L"80000001"]=text(L"old");auto lowerPlan=planCatalog({{cardName,lower}},L"new",owns);
 check(lowerPlan.code==0&&lowerPlan.after.at(cardName).count(L"atr")&&!lowerPlan.after.at(cardName).count(L"ATR"));
 check(planCatalog({{cardName,foreign}},L"new",owns).code==conflict);
 check(planCatalog({{L"cie id flutter prototype web cie_1",{}}},L"new",owns).code==conflict);
 auto wildcard=foreign;wildcard.erase(L"ATRMask");check(planCatalog({{L"Foreign incomplete mask",wildcard}},L"new",owns).code==conflict);
 auto collision=fresh.after;collision[std::wstring(cardName)+L" CIE_1"][L"ATR"]=binary(cardCatalog[1].atr);
 check(planCatalog(collision,L"new",owns).code==conflict);
 Values unrelated{{L"ATR",binary({1,2,3})},{L"ATRMask",binary({255,255,255})},{L"note",text(L"untouched")}};
 Database withForeign{{L"Foreign unrelated",unrelated}};MemoryStore mixed;mixed.state=withForeign;
 check(applyCatalog(mixed,planCatalog(withForeign,L"new",owns))==0&&mixed.state.at(L"Foreign unrelated")==unrelated);
 auto stale=fresh;MemoryStore raced;raced.state=withForeign;check(applyCatalog(raced,stale)==conflict&&raced.calls==0);
 CatalogPlan removal;removal.before=mixed.state;check(applyCatalog(mixed,removal)==0&&mixed.state==withForeign);
 // Exercise the real Win32 adapter under an isolated HKCU key, no PC/SC/UAC.
 auto key=L"Software\\CIEIDInstallerTests\\catalog-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64());
 RegistryStore registry(HKEY_CURRENT_USER,key);check(registry.read().empty());check(!registry.write(L"Foreign",{}));
 check(applyCatalog(registry,fresh)==0);check(registry.read()==fresh.after);
 auto prior=registry.read();auto update=planCatalog(prior,L"old",owns);check(applyCatalog(registry,update)==0);check(registry.read()==update.after);
 CatalogPlan remove;remove.before=registry.read();check(applyCatalog(registry,remove)==0);check(registry.read().empty());
 check(RegDeleteKeyExW(HKEY_CURRENT_USER,key.c_str(),KEY_WOW64_64KEY,0)==ERROR_SUCCESS);
 std::cout<<checks<<" catalog/registry checks passed; no card, reader, service, HKLM, user cache or UAC\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}catch(int c){std::cerr<<"Registry error "<<c<<'\n';return 1;}
}
