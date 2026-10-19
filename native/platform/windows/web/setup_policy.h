// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <string>
#include <vector>
#include <algorithm>
namespace cie_setup {
inline constexpr wchar_t cardName[]=L"CIE ID Flutter Prototype Web";
// SCard provider IDs: PRIMARY=1 accepts a GUID, CSP=2 accepts a CSP name.
inline constexpr unsigned cspProvider=2, kspProvider=3, moduleProvider=0x80000001;
enum Code { installed=0, administratorRequired=2, conflict=3, readerUnavailable=4,
 cardUnavailable=5, invalidPackage=6, fileFailure=7, registrationFailure=8,
 recoveryRequired=9, needsElevation=10 };
inline bool ownedName(const std::wstring& value){
 const std::wstring base(cardName);
 return value==base||(value.size()==base.size()+17&&value.compare(0,base.size()+1,base+L" ")==0&&
   std::all_of(value.begin()+base.size()+1,value.end(),[](wchar_t c){return (c>=L'0'&&c<=L'9')||(c>=L'a'&&c<=L'f');}));
}
inline bool foreignMatch(const std::vector<std::wstring>& names){
 return std::any_of(names.begin(),names.end(),[](const auto& n){return !ownedName(n);});
}
// Windows command-line escaping, not shell quoting. No cmd.exe or PowerShell.
inline std::wstring quote(const std::wstring& value){
 std::wstring out=L"\"";size_t slashes=0;
 for(auto c:value){if(c==L'\\'){++slashes;continue;}
  if(c==L'\"')out.append(slashes*2+1,L'\\');else out.append(slashes,L'\\');
  slashes=0;out+=c;
 }out.append(slashes*2,L'\\');return out+L"\"";
}
inline bool validReader(const std::wstring& value){return !value.empty()&&value.size()<=4096&&value.find(L'\0')==std::wstring::npos;}
template<class Set,class Forget,class Verify>
int publishBindings(bool created,Set set,Forget forget,Verify verify,
 const std::wstring& previousCsp,const std::wstring& previousKsp,const std::wstring& previousModule,const std::wstring& module){
 bool good=set(cspProvider,L"Microsoft Base Smart Card Crypto Provider")==0;
 if(good)good=set(kspProvider,L"Microsoft Smart Card Key Storage Provider")==0;
 if(good)good=set(moduleProvider,module)==0;
 if(good&&verify())return installed;
 if(created)return forget()?registrationFailure:recoveryRequired;
 // Attempt every restoration even when an earlier restoration fails.
 bool restored=set(cspProvider,previousCsp)==0;
 if(set(kspProvider,previousKsp))restored=false;
 if(set(moduleProvider,previousModule))restored=false;
 return restored?registrationFailure:recoveryRequired;
}
}
