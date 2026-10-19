// SPDX-License-Identifier: BSD-3-Clause
#include "paired_store.h"
#include <cstring>
#ifdef __APPLE__
#include <Security/Security.h>
#elif defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <wincred.h>
#include "windows_credential_limits.h"
#endif
namespace cie_pairing {
namespace {
void checkPrefix(const char* p){if(!p||std::strlen(p)!=4||!std::all_of(p,p+4,[](char c){return c>='0'&&c<='9';}))throw std::runtime_error("pairing_invalid_record");}
#ifdef __APPLE__
struct Object {CFTypeRef p=nullptr;~Object(){if(p)CFRelease(p);} };
struct Query {
 CFMutableDictionaryRef d=CFDictionaryCreateMutable(nullptr,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 Query(const std::string& id={},bool publicData=false){
  if(!d)throw std::runtime_error("pairing_store_unavailable");
  CFDictionarySetValue(d,kSecClass,kSecClassGenericPassword);
  Object s{CFStringCreateWithCString(nullptr,(std::string(service)+(publicData?".public.v2":"")).c_str(),kCFStringEncodingUTF8)};
  CFDictionarySetValue(d,kSecAttrService,s.p);
  // Local to this Mac, never iCloud-synchronised.
  CFDictionarySetValue(d,kSecAttrSynchronizable,kCFBooleanFalse);
  if(!id.empty()){Object a{CFStringCreateWithCString(nullptr,id.c_str(),kCFStringEncodingUTF8)};CFDictionarySetValue(d,kSecAttrAccount,a.p);}
 }
 ~Query(){CFRelease(d);}
};
void status(OSStatus s){if(s!=errSecSuccess)throw StoreError(s);}
void eraseItem(const std::string& id,bool publicData){
 Query lookup(id,publicData);Object ref;
 // Do not read secret bytes or request a PIN/Keychain prompt for cleanup.
 CFDictionarySetValue(lookup.d,kSecReturnPersistentRef,kCFBooleanTrue);
 CFDictionarySetValue(lookup.d,kSecUseAuthenticationUI,kSecUseAuthenticationUIFail);
 auto s=SecItemCopyMatching(lookup.d,&ref.p);if(s==errSecItemNotFound)return;status(s);
 if(!ref.p||CFGetTypeID(ref.p)!=CFDataGetTypeID())throw StoreError(errSecParam);
 const void* refs[]={ref.p};Object items{CFArrayCreate(nullptr,refs,1,&kCFTypeArrayCallBacks)};
 const void* keys[]={kSecClass,kSecMatchItemList,kSecUseAuthenticationUI};
 const void* values[]={kSecClassGenericPassword,items.p,kSecUseAuthenticationUIFail};
 Object deletion{CFDictionaryCreate(nullptr,keys,values,3,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks)};
 // macOS SecItemDelete accepts persistent refs through kSecMatchItemList.
 s=SecItemDelete((CFDictionaryRef)deletion.p);if(s!=errSecItemNotFound)status(s);
}
#elif defined(_WIN32)
std::wstring target(const std::string& id){std::string s=std::string(service)+"/"+id;return std::wstring(s.begin(),s.end());}
#endif
}
bool supported(){
#if defined(__APPLE__) || defined(_WIN32)
 return true;
#else
 return false;
#endif
}
bool read(const std::string& id,Secret& out){
 checkId(id);if(invalidated(id))return false;
#ifdef __APPLE__
 Query q(id);CFDictionarySetValue(q.d,kSecReturnData,kCFBooleanTrue);Object value;
 auto s=SecItemCopyMatching(q.d,&value.p);if(s==errSecItemNotFound)return false;status(s);
 if(!value.p||CFGetTypeID(value.p)!=CFDataGetTypeID()||CFDataGetLength((CFDataRef)value.p)!=4)throw std::runtime_error("pairing_invalid_record");
 std::memcpy(out.bytes.data(),CFDataGetBytePtr((CFDataRef)value.p),4);
#elif defined(_WIN32)
 PCREDENTIALW value=nullptr;auto t=target(id);
 if(!CredReadW(t.c_str(),CRED_TYPE_GENERIC,0,&value)){if(GetLastError()==ERROR_NOT_FOUND)return false;throw std::runtime_error("pairing_store_unavailable");}
 struct Free{PCREDENTIALW p;~Free(){if(p){if(p->CredentialBlob)SecureZeroMemory(p->CredentialBlob,p->CredentialBlobSize);CredFree(p);}}} free{value};
 if(value->CredentialBlobSize!=4||!value->CredentialBlob)throw std::runtime_error("pairing_invalid_record");
 std::memcpy(out.bytes.data(),value->CredentialBlob,4);
#else
 throw std::runtime_error("pairing_store_unavailable");
#endif
 out.bytes[4]=0;checkPrefix(out.bytes.data());return true;
}
void write(const std::string& id,const char* prefix){
 checkId(id);checkPrefix(prefix);
#ifdef __APPLE__
 Query q(id);Object data{CFDataCreate(nullptr,(const UInt8*)prefix,4)};
 const void* k[]={kSecValueData};const void* v[]={data.p};Object attrs{CFDictionaryCreate(nullptr,k,v,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks)};
 auto s=SecItemUpdate(q.d,(CFDictionaryRef)attrs.p);
 if(s==errSecItemNotFound){CFDictionarySetValue(q.d,kSecValueData,data.p);CFDictionarySetValue(q.d,kSecAttrAccessible,kSecAttrAccessibleWhenUnlockedThisDeviceOnly);s=SecItemAdd(q.d,nullptr);}
 status(s);
#elif defined(_WIN32)
 auto t=target(id);CREDENTIALW c{};c.Type=CRED_TYPE_GENERIC;c.TargetName=t.data();c.CredentialBlobSize=4;c.CredentialBlob=(LPBYTE)prefix;
 // Generic credentials are scoped to the current Windows user on this PC.
 c.Persist=CRED_PERSIST_LOCAL_MACHINE;c.UserName=const_cast<LPWSTR>(L"CIE ID");
 if(!CredWriteW(&c,0))throw std::runtime_error("pairing_store_unavailable");
#else
 throw std::runtime_error("pairing_store_unavailable");
#endif
}
void erase(const std::string& id){
 checkId(id);
#ifdef __APPLE__
 eraseItem(id,false);
#elif defined(_WIN32)
 auto t=target(id);if(!CredDeleteW(t.c_str(),CRED_TYPE_GENERIC,0)&&GetLastError()!=ERROR_NOT_FOUND)throw StoreError(GetLastError());
#else
 throw std::runtime_error("pairing_store_unavailable");
#endif
}
std::vector<std::string> list(){
 std::vector<std::string> ids;
#ifdef __APPLE__
 Query q;CFDictionarySetValue(q.d,kSecReturnAttributes,kCFBooleanTrue);CFDictionarySetValue(q.d,kSecMatchLimit,kSecMatchLimitAll);Object value;
 auto s=SecItemCopyMatching(q.d,&value.p);if(s==errSecItemNotFound)return ids;status(s);
 if(!value.p||CFGetTypeID(value.p)!=CFArrayGetTypeID())throw std::runtime_error("pairing_invalid_record");
 auto a=(CFArrayRef)value.p;
 for(CFIndex i=0;i<CFArrayGetCount(a);++i){auto d=(CFDictionaryRef)CFArrayGetValueAtIndex(a,i);auto account=CFDictionaryGetValue(d,kSecAttrAccount);char name[256]{};
 if(!account||CFGetTypeID(account)!=CFStringGetTypeID()||!CFStringGetCString((CFStringRef)account,name,sizeof(name),kCFStringEncodingUTF8)||!validId(name))throw std::runtime_error("pairing_invalid_record");ids.emplace_back(name);}
#elif defined(_WIN32)
 DWORD count=0;PCREDENTIALW* records=nullptr;auto f=target("*");
 if(!CredEnumerateW(f.c_str(),0,&count,&records)){if(GetLastError()==ERROR_NOT_FOUND)return ids;throw std::runtime_error("pairing_store_unavailable");}
 struct Free{PCREDENTIALW* p;DWORD n;~Free(){for(DWORD i=0;i<n;++i)if(p[i]->CredentialBlob)SecureZeroMemory(p[i]->CredentialBlob,p[i]->CredentialBlobSize);CredFree(p);}} free{records,count};
 auto base=target("");for(DWORD i=0;i<count;++i){auto c=records[i];std::wstring t=c->TargetName?c->TargetName:L"";
 if(c->Type!=CRED_TYPE_GENERIC||t.compare(0,base.size(),base))continue;auto tail=t.substr(base.size());if(tail.find(L'/')!=std::wstring::npos)continue;std::string id(tail.begin(),tail.end());checkId(id);ids.push_back(id);}
#else
 throw std::runtime_error("pairing_store_unavailable");
#endif
 ids.erase(std::remove_if(ids.begin(),ids.end(),[](const auto& id){return invalidated(id);}),ids.end());
 std::sort(ids.begin(),ids.end());if(ids.size()>256)throw std::runtime_error("pairing_limit");return ids;
}
std::vector<uint8_t> readPublic(const std::string& id){checkId(id);
#ifdef __APPLE__
 Query q(id,true);CFDictionarySetValue(q.d,kSecReturnData,kCFBooleanTrue);CFDictionarySetValue(q.d,kSecUseAuthenticationUI,kSecUseAuthenticationUIFail);Object data;
 auto s=SecItemCopyMatching(q.d,&data.p);if(s==errSecItemNotFound)return {};status(s);
 if(!data.p||CFGetTypeID(data.p)!=CFDataGetTypeID())throw std::runtime_error("pairing_public_invalid");
 auto n=CFDataGetLength((CFDataRef)data.p);if(n<=0||n>9000)throw std::runtime_error("pairing_public_invalid");
 auto p=CFDataGetBytePtr((CFDataRef)data.p);return {p,p+n};
#elif defined(_WIN32)
 auto t=target(id);t+=L"/public.v2";PCREDENTIALW data=nullptr;
 if(!CredReadW(t.c_str(),CRED_TYPE_GENERIC,0,&data)){if(GetLastError()==ERROR_NOT_FOUND)return {};throw std::runtime_error("pairing_store_unavailable");}
 struct Free{PCREDENTIALW p;~Free(){CredFree(p);}} free{data};
 if(!data->CredentialBlob||!data->CredentialBlobSize||data->CredentialBlobSize>9000)throw std::runtime_error("pairing_public_invalid");
 return {data->CredentialBlob,data->CredentialBlob+data->CredentialBlobSize};
#else
 throw std::runtime_error("pairing_store_unavailable");
#endif
}
void writePublic(const std::string& id,const std::vector<uint8_t>& bytes){checkId(id);if(bytes.empty()||bytes.size()>9000)throw std::runtime_error("pairing_public_invalid");
#ifdef __APPLE__
 Query q(id,true);Object data{CFDataCreate(nullptr,bytes.data(),bytes.size())};
 const void* k[]={kSecValueData};const void* v[]={data.p};Object attrs{CFDictionaryCreate(nullptr,k,v,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks)};
 auto s=SecItemUpdate(q.d,(CFDictionaryRef)attrs.p);if(s==errSecItemNotFound){CFDictionarySetValue(q.d,kSecValueData,data.p);CFDictionarySetValue(q.d,kSecAttrAccessible,kSecAttrAccessibleWhenUnlockedThisDeviceOnly);s=SecItemAdd(q.d,nullptr);}status(s);
#elif defined(_WIN32)
 if(bytes.size()>cie_windows::credentialBlobLimit)throw std::runtime_error("pairing_public_too_large");
 auto t=target(id);t+=L"/public.v2";CREDENTIALW c{};c.Type=CRED_TYPE_GENERIC;c.TargetName=t.data();c.CredentialBlobSize=bytes.size();c.CredentialBlob=(LPBYTE)bytes.data();c.Persist=CRED_PERSIST_LOCAL_MACHINE;c.UserName=const_cast<LPWSTR>(L"CIE ID public enrollment v2");
 if(!CredWriteW(&c,0))throw std::runtime_error("pairing_store_unavailable");
#else
 throw std::runtime_error("pairing_store_unavailable");
#endif
}
void erasePublic(const std::string& id){checkId(id);
#ifdef __APPLE__
 eraseItem(id,true);
#elif defined(_WIN32)
 auto t=target(id);t+=L"/public.v2";if(!CredDeleteW(t.c_str(),CRED_TYPE_GENERIC,0)&&GetLastError()!=ERROR_NOT_FOUND)throw std::runtime_error("pairing_store_unavailable");
#else
 throw std::runtime_error("pairing_store_unavailable");
#endif
}
std::vector<std::string> listPublic(){std::vector<std::string> ids;
#ifdef __APPLE__
 Query q({},true);CFDictionarySetValue(q.d,kSecReturnAttributes,kCFBooleanTrue);CFDictionarySetValue(q.d,kSecMatchLimit,kSecMatchLimitAll);Object data;auto s=SecItemCopyMatching(q.d,&data.p);if(s==errSecItemNotFound)return ids;status(s);
 if(!data.p||CFGetTypeID(data.p)!=CFArrayGetTypeID())throw std::runtime_error("pairing_public_invalid");
 auto array=(CFArrayRef)data.p;for(CFIndex i=0;i<CFArrayGetCount(array);++i){auto d=(CFDictionaryRef)CFArrayGetValueAtIndex(array,i);auto account=CFDictionaryGetValue(d,kSecAttrAccount);char id[256]{};
 if(!account||CFGetTypeID(account)!=CFStringGetTypeID()||!CFStringGetCString((CFStringRef)account,id,sizeof(id),kCFStringEncodingUTF8)||!validId(id))throw std::runtime_error("pairing_public_invalid");ids.emplace_back(id);}
#elif defined(_WIN32)
 DWORD n=0;PCREDENTIALW* data=nullptr;auto filter=target("*");if(!CredEnumerateW(filter.c_str(),0,&n,&data)){if(GetLastError()==ERROR_NOT_FOUND)return ids;throw std::runtime_error("pairing_store_unavailable");}
 struct Free{PCREDENTIALW* p;~Free(){CredFree(p);}} free{data};auto base=target("");std::wstring suffix=L"/public.v2";
 for(DWORD i=0;i<n;++i){std::wstring t=data[i]->TargetName?data[i]->TargetName:L"";if(data[i]->Type!=CRED_TYPE_GENERIC||t.compare(0,base.size(),base)||t.size()<=base.size()+suffix.size()||t.compare(t.size()-suffix.size(),suffix.size(),suffix))continue;
 auto tail=t.substr(base.size(),t.size()-base.size()-suffix.size());std::string id(tail.begin(),tail.end());checkId(id);ids.push_back(id);}
#else
 throw std::runtime_error("pairing_store_unavailable");
#endif
 std::sort(ids.begin(),ids.end());if(ids.size()>256)throw std::runtime_error("pairing_limit");return ids;
}

}
