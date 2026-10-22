// SPDX-License-Identifier: BSD-3-Clause
// Use the actual Windows publication code and WinCrypt properties. Replace
// only the system-store opening and read-only component registry observations.
// There is no fallback to MY, the real registry, readers or an installed DLL.
#include <windows.h>
#include <wincrypt.h>
#include <winscard.h>
#include <ncrypt.h>
#include <string>
#include <cstring>
#include "cie_bridge.h"
#include "web_container_win.h"
#include "windows_public_certificate_fixture.h"
namespace {
struct MemoryStore {
 HCERTSTORE value=CertOpenStore(CERT_STORE_PROV_MEMORY,0,0,CERT_STORE_CREATE_NEW_FLAG,nullptr);
 ~MemoryStore(){if(value)CertCloseStore(value,0);}
} memory;
bool failStore=false;
std::wstring component;
const wchar_t cardName[]=L"CIE ID Flutter Prototype Web CIE_8";
HCERTSTORE memoryOpen(LPCSTR provider,DWORD,HCRYPTPROV_LEGACY,DWORD flags,const void* name){
 if(provider!=CERT_STORE_PROV_SYSTEM_W||flags!=CERT_SYSTEM_STORE_CURRENT_USER||!name||std::wcscmp(static_cast<const wchar_t*>(name),L"MY"))return nullptr;
 return !failStore&&memory.value?CertDuplicateStore(memory.value):nullptr;
}
LONG fakeContext(DWORD,LPCVOID,LPCVOID,LPSCARDCONTEXT out){*out=1;return 0;}
LONG fakeRelease(SCARDCONTEXT){return 0;}
LONG fakeCards(SCARDCONTEXT,const BYTE*,const GUID*,DWORD,LPWSTR output,LPDWORD n){
 const DWORD size=sizeof(cardName)/sizeof(wchar_t)+1;
 if(output&&*n<size){*n=size;return SCARD_E_INSUFFICIENT_BUFFER;}
 if(output){std::memcpy(output,cardName,sizeof(cardName));output[size-1]=0;}*n=size;return 0;
}
LONG fakeProvider(SCARDCONTEXT,LPCWSTR name,DWORD type,LPWSTR output,LPDWORD n){
 if(std::wcscmp(name,cardName))return SCARD_E_UNKNOWN_CARD;
 std::wstring value=type==3?MS_SMART_CARD_KEY_STORAGE_PROVIDER:type==0x80000001?component:L"";
 if(value.empty())return SCARD_E_INVALID_PARAMETER;
 auto size=static_cast<DWORD>(value.size()+1);if(!output||*n<size){*n=size;return SCARD_E_INSUFFICIENT_BUFFER;}
 std::memcpy(output,value.c_str(),size*sizeof(wchar_t));*n=size;return 0;
}
}
#define CertOpenStore memoryOpen
#define SCardEstablishContext fakeContext
#define SCardReleaseContext fakeRelease
#define SCardListCardsW fakeCards
#define SCardGetCardTypeProviderNameW fakeProvider
#include "../src/web_cert_store.cpp"
#undef CertOpenStore
extern "C" CIE_EXPORT void test_component_path(const wchar_t* path){component=path?path:L"";}
extern "C" CIE_EXPORT void test_fail_certificate_store(int value){failStore=value!=0;}
extern "C" CIE_EXPORT unsigned test_certificate_count(){
 unsigned n=0;PCCERT_CONTEXT c=nullptr;while((c=CertEnumCertificatesInStore(memory.value,c)))++n;return n;
}
extern "C" CIE_EXPORT unsigned test_browser_binding(){
 auto c=CertEnumCertificatesInStore(memory.value,nullptr);if(!c)return 0;
 struct Free{PCCERT_CONTEXT c;~Free(){CertFreeCertificateContext(c);}} free{c};
 unsigned flags=c->cbCertEncoded==sizeof(testCertificate)&&!std::memcmp(c->pbCertEncoded,testCertificate,sizeof(testCertificate))?1:0;
 DWORD size=0;if(CertGetCertificateContextProperty(c,CERT_KEY_PROV_INFO_PROP_ID,nullptr,&size)){
  std::vector<BYTE> data(size);if(CertGetCertificateContextProperty(c,CERT_KEY_PROV_INFO_PROP_ID,data.data(),&size)){
   auto p=reinterpret_cast<CRYPT_KEY_PROV_INFO*>(data.data());
   if(p->pwszProvName&&!std::wcscmp(p->pwszProvName,MS_SMART_CARD_KEY_STORAGE_PROVIDER)&&p->dwKeySpec==CERT_NCRYPT_KEY_SPEC)flags|=2;
   if(p->pwszContainerName&&p->pwszContainerName==cie_web_store::containerName(cie_web_store::containerGuid("TEST")))flags|=4;
  }
 }
 if(CertGetCertificateContextProperty(c,CERT_FIRST_USER_PROP_ID+71,nullptr,&size))flags|=8;
 if(CertGetCertificateContextProperty(c,CERT_FRIENDLY_NAME_PROP_ID,nullptr,&size)){
  std::vector<wchar_t> label((size+sizeof(wchar_t)-1)/sizeof(wchar_t));
  if(CertGetCertificateContextProperty(c,CERT_FRIENDLY_NAME_PROP_ID,label.data(),&size)&&!label.empty()&&label.back()==0&&std::wstring(label.data())==L"Firma con CIE · Accesso ai siti")flags|=16;
 }
 return flags;
}
extern "C" CIE_EXPORT int test_add_foreign_certificate(){
 return CertAddEncodedCertificateToStore(memory.value,X509_ASN_ENCODING,testCertificate,sizeof(testCertificate),CERT_STORE_ADD_NEW,nullptr)?1:0;
}
