// SPDX-License-Identifier: BSD-3-Clause
#include <windows.h>
#include <shellapi.h>
#include <winscard.h>
#include <iostream>
#include <stdexcept>
#include <map>
#include "setup_policy.h"
#include "card_identification.h"
#if defined(__MINGW32__) && !defined(SCARD_PROVIDER_KSP)
// Windows SDK defines this provider ID; older MinGW headers omit the name.
static constexpr unsigned SCARD_PROVIDER_KSP=3;
#endif
int main(){unsigned checks=0;auto check=[&](bool v){++checks;if(!v)throw std::runtime_error("setup policy check "+std::to_string(checks));};try{
 static_assert(cie_setup::cspProvider==SCARD_PROVIDER_CSP);
 static_assert(cie_setup::kspProvider==SCARD_PROVIDER_KSP);
 static_assert(cie_setup::moduleProvider==0x80000001);
 std::vector<unsigned> providerIds;
 check(cie_setup::publishBindings(true,[&](unsigned key,const std::wstring&){providerIds.push_back(key);return key==SCARD_PROVIDER_PRIMARY?ERROR_INVALID_PARAMETER:ERROR_SUCCESS;},[]{return true;},[]{return true;},L"",L"",L"",L"new")==0);
 check(providerIds==std::vector<unsigned>{SCARD_PROVIDER_CSP,SCARD_PROVIDER_KSP,0x80000001});
 check(cie_setup::ownedName(cie_setup::cardName));
 check(cie_setup::ownedName(std::wstring(cie_setup::cardName)+L" 0123456789abcdef"));
 for(auto suffix:{L" Evil",L" 0123456789abcde",L" 0123456789abcdef0",L" 0123456789abcdeg"})check(!cie_setup::ownedName(std::wstring(cie_setup::cardName)+suffix));
 check(!cie_setup::foreignMatch({}));check(!cie_setup::foreignMatch({cie_setup::cardName}));
 check(cie_setup::foreignMatch({L"Official CIE Middleware"}));check(cie_setup::foreignMatch({cie_setup::cardName,L"Official CIE Middleware"}));
 check(!cie_setup::validReader(L""));check(!cie_setup::validReader(std::wstring(4097,L'x')));check(!cie_setup::validReader(std::wstring(L"a\0b",3)));
 for(const auto& input:std::vector<std::wstring>{L"Reader CLESS 0",L"Reader \"name\"",std::wstring(L"Reader ")+wchar_t(92),L"Reader & %PATH% ;",L"Lettore \u00e0"}){
  std::wstring value(input);auto text=L"helper "+cie_setup::quote(value);int count=0;auto argv=CommandLineToArgvW(text.c_str(),&count);check(argv&&count==2&&value==argv[1]);LocalFree(argv);
 }
 cie_identification::ReadCommands commands;
 for(uint8_t ins:{0x20,0x24,0x2c,0x82,0x88,0xd6,0xda}){uint8_t apdu[]={0,ins,0,0};check(!commands.accept(apdu,4));}
 for(unsigned i=0;i<16;++i){uint8_t apdu[]={0,0xa4,0,0};check(commands.accept(apdu,4));}
 uint8_t extra[]={0,0xb0,0,0};check(!commands.accept(extra,4));
 for(int failed=1;failed<=3;++failed){
  std::map<unsigned,std::wstring> before{{SCARD_PROVIDER_CSP,L"old csp"},{SCARD_PROVIDER_KSP,L"old ksp"},{0x80000001,L"old module"}},state=before;int calls=0;
  auto set=[&](unsigned key,const std::wstring& v){if(++calls==failed)return 5;state[key]=v;return 0;};
  check(cie_setup::publishBindings(false,set,[]{return true;},[]{return true;},before[SCARD_PROVIDER_CSP],before[SCARD_PROVIDER_KSP],before[0x80000001],L"new module")==cie_setup::registrationFailure);
  check(state==before);
 }
 for(bool deleted:{false,true}){
  auto set=[](unsigned,const std::wstring&){return 5;};
  check(cie_setup::publishBindings(true,set,[&]{return deleted;},[]{return true;},L"",L"",L"",L"new")== (deleted?cie_setup::registrationFailure:cie_setup::recoveryRequired));
 }
 check(cie_setup::publishBindings(false,[](unsigned,const std::wstring&){return 5;},[]{return false;},[]{return false;},L"old",L"old",L"old",L"new")==cie_setup::recoveryRequired);
 bool forgot=false;
 check(cie_setup::publishBindings(true,[](unsigned,const std::wstring&){return 0;},[&]{forgot=true;return true;},[]{return false;},L"",L"",L"",L"new")==cie_setup::registrationFailure);
 check(forgot);
 check(cie_setup::publishBindings(true,[](unsigned,const std::wstring&){return 0;},[]{return true;},[]{return true;},L"",L"",L"",L"new")==0);
 std::cout<<checks<<" setup policy checks passed; no UAC, PCSC, registry or credentials\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
