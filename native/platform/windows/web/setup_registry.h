// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <windows.h>
#include "setup_catalog.h"
namespace cie_setup {
// The installer uses the native 64-bit Calais database directly. No resource
// manager, reader enumeration, card connection or service start is necessary.
// Tests use this same adapter under a unique HKCU test key, never HKLM.
class RegistryStore {
 HKEY hive_;std::wstring path_;
 struct Key{HKEY h=nullptr;~Key(){if(h)RegCloseKey(h);}};
public:
 RegistryStore(HKEY hive,std::wstring path):hive_(hive),path_(std::move(path)){}
 Database read()const{
  Key base;auto status=RegOpenKeyExW(hive_,path_.c_str(),0,KEY_READ|KEY_WOW64_64KEY,&base.h);
  if(status==ERROR_FILE_NOT_FOUND)return {};if(status)throw int(registrationFailure);
  Database result;
  for(DWORD i=0;;++i){wchar_t name[256];DWORD n=256;status=RegEnumKeyExW(base.h,i,name,&n,nullptr,nullptr,nullptr,nullptr);
   if(status==ERROR_NO_MORE_ITEMS)break;if(status)throw int(registrationFailure);
   Key child;if(RegOpenKeyExW(base.h,name,0,KEY_READ|KEY_WOW64_64KEY,&child.h))throw int(registrationFailure);
   DWORD children=0;if(RegQueryInfoKeyW(child.h,nullptr,nullptr,nullptr,&children,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr))throw int(registrationFailure);
   if(children&&ownedName(name))throw int(conflict);
   Values values;
   for(DWORD j=0;;++j){wchar_t label[16384];DWORD len=16384,type=0,size=0;
    status=RegEnumValueW(child.h,j,label,&len,nullptr,&type,nullptr,&size);if(status==ERROR_NO_MORE_ITEMS)break;
    if(status||size>1048576)throw int(registrationFailure);
    Value value{type,std::vector<uint8_t>(size)};len=16384;
    if(RegEnumValueW(child.h,j,label,&len,nullptr,&type,value.bytes.data(),&size))throw int(registrationFailure);
    value.type=type;value.bytes.resize(size);values.emplace(label,std::move(value));
   }result.emplace(name,std::move(values));
  }return result;
 }
 bool write(const std::wstring& name,const Values& values)const{
  if(!ownedName(name))return false;
  Key key;if(RegCreateKeyExW(hive_,(path_+L"\\"+name).c_str(),0,nullptr,0,KEY_READ|KEY_WRITE|KEY_WOW64_64KEY,nullptr,&key.h,nullptr))return false;
  for(const auto& value:values)if(RegSetValueExW(key.h,value.first.c_str(),0,value.second.type,value.second.bytes.data(),static_cast<DWORD>(value.second.bytes.size())))return false;
  // Remove values added by a failed attempt when restoring an older snapshot.
  for(DWORD i=0;;){wchar_t nameValue[16384];DWORD n=16384;auto status=RegEnumValueW(key.h,i,nameValue,&n,nullptr,nullptr,nullptr,nullptr);
   if(status==ERROR_NO_MORE_ITEMS)break;if(status)return false;
   if(!values.count(nameValue)){if(RegDeleteValueW(key.h,nameValue))return false;}else ++i;
  }return true;
 }
 bool erase(const std::wstring& name)const{
  if(!ownedName(name))return false;
  auto status=RegDeleteKeyExW(hive_,(path_+L"\\"+name).c_str(),KEY_WOW64_64KEY,0);
  return status==ERROR_SUCCESS||status==ERROR_FILE_NOT_FOUND;
 }
};
}
