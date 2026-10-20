// SPDX-License-Identifier: BSD-3-Clause
#include "web_cert_store.h"
#include "paired_store.h"
#include "local_cache.h"
#include <cstring>
#if defined(_WIN32) && !defined(CIE_WEB_TEST_STORE)
#include <windows.h>
#include <bcrypt.h>
#include <ncrypt.h>
#include <winscard.h>
#include <filesystem>
#include "web_container_win.h"
#include "../platform/windows/web/setup_policy.h"
#endif
#if defined(__linux__) && !defined(CIE_WEB_TEST_STORE)
#include <dlfcn.h>
#include <filesystem>
#endif
namespace cie_web_store {
#if defined(_WIN32) && !defined(CIE_WEB_TEST_STORE)
namespace {
constexpr DWORD markerProperty=CERT_FIRST_USER_PROP_ID+71;
struct Store{HCERTSTORE p=CertOpenStore(CERT_STORE_PROV_SYSTEM_W,0,0,CERT_SYSTEM_STORE_CURRENT_USER,L"MY");~Store(){if(p)CertCloseStore(p,0);}};
std::string markerBase(const std::string& id){return std::string(cie_pairing::service)+".web/"+id+"/";}
bool checkCertificateOwnership(HCERTSTORE store,const std::string& id,const uint8_t* der,uint32_t length){
 auto prefix=markerBase(id);bool found=false;PCCERT_CONTEXT current=nullptr;
 while((current=CertEnumCertificatesInStore(store,current))){
  if(current->cbCertEncoded!=length||std::memcmp(current->pbCertEncoded,der,length))continue;
  DWORD size=0;bool owned=CertGetCertificateContextProperty(current,markerProperty,nullptr,&size)&&size&&size<=512;
  std::string marker(owned?size:0,'\0');
  owned=owned&&CertGetCertificateContextProperty(current,markerProperty,marker.data(),&size)&&marker.compare(0,prefix.size(),prefix)==0;
  if(!owned){CertFreeCertificateContext(current);throw std::runtime_error("web_certificate_conflict");}
  found=true;
 }
 return found;
}
void removeCertificates(HCERTSTORE store,const std::string& id,const std::string& keep={}){
 auto prefix=markerBase(id);PCCERT_CONTEXT current=nullptr;
 while((current=CertEnumCertificatesInStore(store,current))){DWORD size=0;
  if(!CertGetCertificateContextProperty(current,markerProperty,nullptr,&size)||size>512||!size)continue;
  std::string marker(size,'\0');if(!CertGetCertificateContextProperty(current,markerProperty,marker.data(),&size))continue;
  if(marker.compare(0,prefix.size(),prefix)||marker==keep)continue;
  if(!CertDeleteCertificateFromStore(CertDuplicateCertificateContext(current))){CertFreeCertificateContext(current);throw std::runtime_error("web_store_unavailable");}
 }
}
}
std::vector<std::string> list(){cie_cache::Store store;return store.list("web");}
bool componentAvailable(){
 SCARDCONTEXT c=0;if(SCardEstablishContext(SCARD_SCOPE_USER,nullptr,nullptr,&c))return false;
 struct Release{SCARDCONTEXT c;~Release(){SCardReleaseContext(c);}} release{c};
 DWORD count=0;if(SCardListCardsW(c,nullptr,nullptr,0,nullptr,&count)||count>65536||count<2)return false;
 std::vector<wchar_t> names(count);if(SCardListCardsW(c,nullptr,nullptr,0,names.data(),&count))return false;
 for(auto name=names.data();*name;name+=wcslen(name)+1){
  if(!cie_setup::ownedName(name))continue;
  wchar_t provider[512]{};DWORD n=512;
  if(SCardGetCardTypeProviderNameW(c,name,3,provider,&n)||std::wstring(provider)!=MS_SMART_CARD_KEY_STORAGE_PROVIDER)continue;
  wchar_t module[4096]{};n=4096;if(SCardGetCardTypeProviderNameW(c,name,0x80000001,module,&n))continue;
  std::error_code ec;auto path=std::filesystem::path(module);if(path.filename()!=L"cie_prototype_minidriver.dll"||!std::filesystem::is_regular_file(path,ec))continue;
  // A previous provider reads Credential Manager. Treat it as an upgrade,
  // rather than silently accepting it for a file-cache enrollment.
  auto library=LoadLibraryExW(path.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if(!library)continue;auto version=reinterpret_cast<DWORD(*)()>(GetProcAddress(library,"CiePairingStorageVersion"));
  bool compatible=version&&version()==3;FreeLibrary(library);if(compatible)return true;
 }
 return false;
}
bool provisioned(const std::string& id,const uint8_t* der,uint32_t size){
 Store store;if(!store.p)return false;try{return read(id)==std::vector<uint8_t>(der,der+size)&&checkCertificateOwnership(store.p,id,der,size);}catch(...){return false;}
}
std::vector<uint8_t> read(const std::string& id){cie_pairing::checkId(id);cie_cache::Store store;auto bytes=store.read("web",id);
 if(bytes.size()>8192)throw std::runtime_error("web_invalid_certificate");return {bytes.begin(),bytes.end()};
}
void write(const std::string& id,const uint8_t* der,uint32_t size){cie_pairing::checkId(id);
 if(!der||!size||size>8192)throw std::runtime_error("web_invalid_certificate");
 Store store;if(!store.p)throw std::runtime_error("web_store_unavailable");
 const bool replace=checkCertificateOwnership(store.p,id,der,size);
 PCCERT_CONTEXT created=CertCreateCertificateContext(X509_ASN_ENCODING,der,size);
 if(!created)throw std::runtime_error("web_invalid_certificate");
 struct Free{PCCERT_CONTEXT p;~Free(){CertFreeCertificateContext(p);}} free{created};
 auto container=containerName(containerGuid(id));CRYPT_KEY_PROV_INFO provider{};provider.pwszContainerName=container.data();provider.pwszProvName=const_cast<LPWSTR>(MS_SMART_CARD_KEY_STORAGE_PROVIDER);provider.dwKeySpec=CERT_NCRYPT_KEY_SPEC;
 BYTE random[16];if(BCryptGenRandom(nullptr,random,sizeof(random),BCRYPT_USE_SYSTEM_PREFERRED_RNG))throw std::runtime_error("web_store_unavailable");
 auto marker=markerBase(id);const char hex[]="0123456789abcdef";for(auto b:random){marker+=hex[b>>4];marker+=hex[b&15];}
 CRYPT_DATA_BLOB tag{static_cast<DWORD>(marker.size()),reinterpret_cast<BYTE*>(marker.data())};
 wchar_t label[]=L"CIE ID · Accesso ai siti";CRYPT_DATA_BLOB friendly{sizeof(label),reinterpret_cast<BYTE*>(label)};
 if(!CertSetCertificateContextProperty(created,CERT_KEY_PROV_INFO_PROP_ID,0,&provider)||!CertSetCertificateContextProperty(created,markerProperty,0,&tag)||!CertSetCertificateContextProperty(created,CERT_FRIENDLY_NAME_PROP_ID,0,&friendly))throw std::runtime_error("web_store_unavailable");
 PCCERT_CONTEXT added=nullptr;
 // Windows MY persists one entry per certificate. Refuse foreign associations
 // before writing; replace only a context already owned by this configuration.
 if(!CertAddCertificateContextToStore(store.p,created,replace?CERT_STORE_ADD_REPLACE_EXISTING:CERT_STORE_ADD_NEW,&added))throw std::runtime_error("web_store_unavailable");
 try{cie_cache::Store cache(true);cie_cache::Bytes bytes(der,der+size);cache.write("web",id,bytes);}
 catch(...){CertDeleteCertificateFromStore(added);throw;}
 CertFreeCertificateContext(added);removeCertificates(store.p,id,marker);
}
void erase(const std::string& id){cie_pairing::checkId(id);Store store;if(!store.p)throw std::runtime_error("web_store_unavailable");removeCertificates(store.p,id);cie_cache::Store cache;cache.erase("web",id);}
int32_t test(const std::string& id){
 auto der=read(id);if(der.empty())return -1;
 auto cert=CertCreateCertificateContext(X509_ASN_ENCODING,der.data(),static_cast<DWORD>(der.size()));if(!cert)return -2;
 struct FreeCert{PCCERT_CONTEXT p;~FreeCert(){CertFreeCertificateContext(p);}} freeCert{cert};
 NCRYPT_PROV_HANDLE provider=0;NCRYPT_KEY_HANDLE key=0;
 struct FreeCng{NCRYPT_PROV_HANDLE* p;NCRYPT_KEY_HANDLE* k;~FreeCng(){if(*k)NCryptFreeObject(*k);if(*p)NCryptFreeObject(*p);}} freeCng{&provider,&key};
 auto status=NCryptOpenStorageProvider(&provider,MS_SMART_CARD_KEY_STORAGE_PROVIDER,0);if(status)return status;
 auto container=containerName(containerGuid(id));status=NCryptOpenKey(provider,&key,container.c_str(),0,NCRYPT_SILENT_FLAG);if(status)return status;
 const BYTE challenge[]="CIE ID Flutter local web-authentication challenge v1";BYTE digest[32];DWORD n=sizeof(digest);
 if(!CryptHashCertificate(0,CALG_SHA_256,0,challenge,sizeof(challenge)-1,digest,&n))return -3;
 BCRYPT_PKCS1_PADDING_INFO padding{BCRYPT_SHA256_ALGORITHM};BYTE signature[256];DWORD size=sizeof(signature);
 // Single explicit private operation. No size query or fallback/retry.
 status=NCryptSignHash(key,&padding,digest,n,signature,sizeof(signature),&size,NCRYPT_PAD_PKCS1_FLAG);if(status)return status;
 BCRYPT_KEY_HANDLE publicKey=0;if(!CryptImportPublicKeyInfoEx2(X509_ASN_ENCODING,&cert->pCertInfo->SubjectPublicKeyInfo,0,nullptr,&publicKey))return -4;
 auto verified=BCryptVerifySignature(publicKey,&padding,digest,n,signature,size,BCRYPT_PAD_PKCS1);BCryptDestroyKey(publicKey);return verified;
}
#elif defined(__linux__) && !defined(CIE_WEB_TEST_STORE)
bool componentAvailable(){
 Dl_info own{};
 if(!dladdr(reinterpret_cast<void*>(&componentAvailable),&own)||!own.dli_fname)return false;
 auto path=std::filesystem::absolute(own.dli_fname).parent_path()/"libcie_linux_pkcs11.so";
 // Read module metadata only: never initialize PKCS#11, enumerate readers or
 // inspect a Firefox profile while the application refreshes its Home.
 void* module=dlopen(path.c_str(),RTLD_LOCAL|RTLD_NOW);if(!module)return false;
 auto version=reinterpret_cast<uint32_t(*)()>(dlsym(module,"CieLinuxWebAbiVersion"));
 bool available=version&&version()==1;dlclose(module);return available;
}
std::vector<std::string> list(){cie_cache::Store store;return store.list("web");}
std::vector<uint8_t> read(const std::string& id){
 cie_pairing::checkId(id);cie_cache::Store store;auto value=store.read("web",id);
 if(value.size()>8192)throw std::runtime_error("web_invalid_certificate");return {value.begin(),value.end()};
}
bool provisioned(const std::string& id,const uint8_t* der,uint32_t size){
 if(!der||!size||size>8192)return false;
 try{return read(id)==std::vector<uint8_t>(der,der+size);}catch(...){return false;}
}
void write(const std::string& id,const uint8_t* der,uint32_t size){
 cie_pairing::checkId(id);if(!der||!size||size>8192)throw std::runtime_error("web_invalid_certificate");
 cie_cache::Bytes value(der,der+size);cie_cache::Store store(true);store.write("web",id,value);
}
void erase(const std::string& id){cie_pairing::checkId(id);cie_cache::Store store;store.erase("web",id);}
int32_t test(const std::string&){return -1;} // Explicit authentication belongs to Firefox.
#else
std::vector<std::string> list(){return {};}
bool componentAvailable(){return false;}
bool provisioned(const std::string&,const uint8_t*,uint32_t){return false;}
std::vector<uint8_t> read(const std::string&){return {};}
void write(const std::string&,const uint8_t*,uint32_t){}
void erase(const std::string&){}
int32_t test(const std::string&){return -1;}
#endif
}
