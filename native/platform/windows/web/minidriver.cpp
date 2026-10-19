// SPDX-License-Identifier: BSD-3-Clause
#include <windows.h>
#include <wincrypt.h>
#include <winscard.h>
#include <bcrypt.h>
#include "cardmod_compat.h"
#include "cie_web.h"
#include "paired_store.h"
#include "web_cert_store.h"
#include "web_container_win.h"
#include "web_policy.h"
#include <algorithm>
#include <string>
#include <vector>
#include <memory>
#include <cstdio>

namespace {
// Let Base CSP/KSP reuse the full PIN across the callbacks of one browser
// handshake. Windows owns the encrypted, per-process cache; the minidriver
// never retains the PIN. Bound reuse instead of caching for the browser's life.
constexpr DWORD websitePinCacheSeconds=60;
// Opt-in per-process diagnostics. Numeric API metadata only: never log PINs,
// identifiers, certificates, APDUs, message hashes or signatures. Normal hosts
// do not set this variable, so no file is opened during ordinary operation.
void diagnostic(const char* operation,DWORD result,DWORD a=0,DWORD b=0,DWORD c=0,DWORD e=0,DWORD f=0) noexcept {
 wchar_t path[32768];DWORD n=GetEnvironmentVariableW(L"CIE_WEB_DIAGNOSTIC_FILE",path,32768);if(!n||n>=32768)return;
 HANDLE h=CreateFileW(path,FILE_APPEND_DATA,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_ALWAYS,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);if(h==INVALID_HANDLE_VALUE)return;
 BY_HANDLE_FILE_INFORMATION info{};
 if(GetFileInformationByHandle(h,&info)&&!(info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))&&info.nNumberOfLinks==1){
  char text[256];int length=snprintf(text,sizeof(text),"%s result=0x%08lx a=0x%08lx b=0x%08lx c=0x%08lx d=0x%08lx e=0x%08lx\n",operation,result,a,b,c,e,f);DWORD written=0;
  if(length>0&&length<static_cast<int>(sizeof(text)))WriteFile(h,text,static_cast<DWORD>(length),&written,nullptr);
 }CloseHandle(h);
}
// Exact callback signatures, including calling convention. Optional mutations
// are explicitly unsupported, not forwarded to the legacy PIN/PUK functions.
template<class T>struct Unsupported;
template<class R,class... A>struct Unsupported<R(WINAPI*)(A...)>{static R WINAPI call(A...){return SCARD_E_UNSUPPORTED_FEATURE;}};
#define UNSUPPORTED(field) d->field=Unsupported<decltype(d->field)>::call
DWORD mapped(int32_t s){
 if(!s)return SCARD_S_SUCCESS;if((s&0xfff0)==0x63c0)return SCARD_W_WRONG_CHV;
 if(s==0x6983)return SCARD_W_CHV_BLOCKED;
 if(s==CIE_WEB_AUTH_REQUIRED)return SCARD_W_SECURITY_VIOLATION;
 if(s==CIE_WEB_ARGUMENT)return SCARD_E_INVALID_PARAMETER;
 if(s==CIE_WEB_ALGORITHM)return SCARD_E_UNSUPPORTED_FEATURE;
 return SCARD_E_COMM_DATA_LOST;
}
struct Provider {
 HMODULE module=nullptr;CieWebSession* session=nullptr;PCARD_DATA card;
 decltype(&cie_web_open) open=nullptr;decltype(&cie_web_close) close=nullptr;
 decltype(&cie_web_identifier) identifier=nullptr;decltype(&cie_web_certificate) certificate=nullptr;
 decltype(&cie_web_set_certificate) setCertificate=nullptr;
 decltype(&cie_web_authenticate) authenticate=nullptr;decltype(&cie_web_sign) sign=nullptr;
 std::string id;std::vector<BYTE> cert;BYTE guid[16]{};
 bool authenticated=false;
 explicit Provider(PCARD_DATA d):card(d){}
 ~Provider(){if(session&&close)close(session);if(module)FreeLibrary(module);}
 template<class T>bool symbol(T& out,const char* name){out=reinterpret_cast<T>(GetProcAddress(module,name));return out!=nullptr;}
 DWORD init(){
  HMODULE own=nullptr;wchar_t path[32768];
  if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(&mapped),&own))return SCARD_F_INTERNAL_ERROR;
  DWORD n=GetModuleFileNameW(own,path,32768);if(!n||n>=32768)return SCARD_F_INTERNAL_ERROR;
  std::wstring file(path,n);auto slash=file.find_last_of(L"\\/");if(slash==std::wstring::npos)return SCARD_F_INTERNAL_ERROR;
  file.resize(slash+1);file+=L"backend\\cie_web.dll";
  module=LoadLibraryExW(file.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
  if(!module||!symbol(open,"cie_web_open")||!symbol(close,"cie_web_close")||!symbol(identifier,"cie_web_identifier")||!symbol(certificate,"cie_web_certificate")||!symbol(setCertificate,"cie_web_set_certificate")||!symbol(authenticate,"cie_web_authenticate")||!symbol(sign,"cie_web_sign"))return SCARD_E_NO_SERVICE;
  decltype(&cie_web_abi_version) version=nullptr;if(!symbol(version,"cie_web_abi_version")||version()!=1)return ERROR_REVISION_MISMATCH;
  auto status=open(card->pbAtr,card->cbAtr,transmit,this,nullptr,&session);if(status)return mapped(status);
  char text[64];uint32_t count=sizeof(text);if(identifier(session,text,&count))return SCARD_F_INTERNAL_ERROR;id=text;
  auto container=cie_web_store::containerGuid(id);memcpy(guid,&container,16);
  return SCARD_S_SUCCESS;
 }
 static int32_t transmit(void* context,const uint8_t* request,uint32_t size,uint8_t* response,uint32_t* length){
  auto p=static_cast<Provider*>(context);DWORD count=*length;
  // Caller owns the transaction: no Connect, BeginTransaction or Reconnect.
  LONG s=SCardTransmit(p->card->hScard,SCARD_PCI_T1,request,size,nullptr,response,&count);*length=count;return s?CIE_WEB_TRANSPORT:0;
 }
 DWORD readCertificate(){if(!cert.empty())return 0;auto cached=cie_web_store::read(id);
  if(!cached.empty()){auto status=setCertificate(session,cached.data(),static_cast<uint32_t>(cached.size()));if(status)return mapped(status);}
  uint8_t buffer[8192];uint32_t size=sizeof(buffer);auto s=certificate(session,buffer,&size);if(s)return mapped(s);cert.assign(buffer,buffer+size);return 0;}
 DWORD newAuthenticationSession(){
  // KSP can collect/validate the PIN using another CARD_DATA context. Public
  // discovery or caller-owned resets may have invalidated this context's IAS
  // selection/secure-messaging state while the PIN dialog was open. Start from
  // known application selection on every explicit authentication callback,
  // never retry an authentication or reuse a previous successful PIN check.
  authenticated=false;if(session)close(session);session=nullptr;
  auto status=open(card->pbAtr,card->cbAtr,transmit,this,id.c_str(),&session);diagnostic("authentication.open",static_cast<DWORD>(status));if(status)return mapped(status);
  if(!cert.empty()){status=setCertificate(session,cert.data(),static_cast<uint32_t>(cert.size()));if(status)return mapped(status);}return 0;
 }
};
Provider* provider(PCARD_DATA d){return d?static_cast<Provider*>(d->pvVendorSpecific):nullptr;}
template<class F>DWORD boundary(F body){try{return body();}catch(...){return SCARD_F_INTERNAL_ERROR;}}
DWORD allocated(PCARD_DATA d,const void* value,DWORD size,PBYTE* out,PDWORD count){
 if(!d||!out||!count)return SCARD_E_INVALID_PARAMETER;*out=nullptr;*count=0;
 auto p=static_cast<PBYTE>(d->pfnCspAlloc(size));if(!p)return ERROR_NOT_ENOUGH_MEMORY;
 memcpy(p,value,size);*out=p;*count=size;return 0;
}
DWORD WINAPI removeContext(PCARD_DATA d){if(!d)return SCARD_E_INVALID_PARAMETER;delete provider(d);d->pvVendorSpecific=nullptr;return 0;}
DWORD WINAPI readFile(PCARD_DATA d,LPSTR directory,LPSTR name,DWORD flags,PBYTE* out,PDWORD count){return boundary([&]()->DWORD{
 if(!provider(d)||!name||!out||!count||flags)return SCARD_E_INVALID_PARAMETER;*out=nullptr;*count=0;auto p=provider(d);
 if(!directory||!*directory){
  if(!strcmp(name,"cardid"))return allocated(d,p->guid,16,out,count);
  if(!strcmp(name,"cardcf")){CARD_CACHE_FILE_FORMAT cache{};cache.bVersion=CARD_CACHE_FILE_CURRENT_VERSION;return allocated(d,&cache,sizeof(cache),out,count);}
  if(!strcmp(name,"cardapps")){char apps[8]={'m','s','c','p',0,0,0,0};return allocated(d,apps,8,out,count);}
 }else if(!strcmp(directory,"mscp")){
  if(!strcmp(name,"cmapfile")){
   auto status=p->readCertificate();if(status)return status;
   CONTAINER_MAP_RECORD map{};GUID g;memcpy(&g,p->guid,sizeof(g));
   auto name=cie_web_store::containerName(g);memcpy(map.wszGuid,name.c_str(),(name.size()+1)*sizeof(wchar_t));
   map.bFlags=CONTAINER_MAP_VALID_CONTAINER|CONTAINER_MAP_DEFAULT_CONTAINER;map.wSigKeySizeBits=2048;return allocated(d,&map,sizeof(map),out,count);
  }
  if(!strcmp(name,"ksc00")){auto s=p->readCertificate();if(s)return s;return allocated(d,p->cert.data(),static_cast<DWORD>(p->cert.size()),out,count);}
 }
 return SCARD_E_FILE_NOT_FOUND;
 });}
DWORD WINAPI authenticate(PCARD_DATA d,PIN_ID pin,DWORD flags,PBYTE input,DWORD size,PBYTE* sessionPin,PDWORD sessionSize,PDWORD attempts){auto result=boundary([&]()->DWORD{
 if(sessionPin)*sessionPin=nullptr;if(sessionSize)*sessionSize=0;if(attempts)*attempts=DWORD(-1);
 auto p=provider(d);if(!p||pin!=ROLE_USER||(flags&~CARD_PIN_SILENT_CONTEXT)||!input||size!=8||!std::all_of(input,input+size,[](BYTE c){return c>='0'&&c<='9';}))return SCARD_E_INVALID_PARAMETER;
 diagnostic("authentication.begin",0,p->authenticated?1:0,p->session?1:0);
 auto restarted=p->newAuthenticationSession();if(restarted)return restarted;
 cie_pairing::Secret secret;
 // Website login uses the same full eight-digit PIN on Windows and macOS.
 // Never reconstruct it from the pairing prefix used for document signing.
 memcpy(secret.bytes.data(),input,8);
 auto status=p->authenticate(p->session,secret.bytes.data(),8);
 diagnostic("core.authenticate",static_cast<DWORD>(status));
 p->authenticated=status==0;
 if(attempts&&(status&0xfff0)==0x63c0)*attempts=status&15;return mapped(status);
 });diagnostic("CardAuthenticateEx",result,pin,flags,size);return result;}
DWORD WINAPI authenticatePin(PCARD_DATA d,LPWSTR user,PBYTE pin,DWORD size,PDWORD attempts){if(!user||wcscmp(user,L"user"))return SCARD_E_INVALID_PARAMETER;return authenticate(d,ROLE_USER,0,pin,size,nullptr,nullptr,attempts);}
DWORD WINAPI deauthenticate(PCARD_DATA d,PIN_SET pins,DWORD flags){
 auto p=provider(d);if(!p||flags||pins!=(1<<ROLE_USER))return SCARD_E_INVALID_PARAMETER;
 diagnostic("CardDeauthenticateEx",SCARD_E_UNSUPPORTED_FEATURE,pins,flags);
 // Forget secure-messaging/auth state. Only the caller may reset the card.
 p->close(p->session);p->session=nullptr;p->authenticated=false;
 // Hardware logout requires a reset. Returning unsupported tells the caller
 // to perform that reset; dropping local state alone is not card logout.
 return SCARD_E_UNSUPPORTED_FEATURE;
}
// Except CARD_DATA, version 0 means version 1. Newer callers may request a
// higher revision; negotiate down to our supported version rather than reject.
DWORD WINAPI capabilities(PCARD_DATA d,PCARD_CAPABILITIES value){if(!provider(d)||!value)return SCARD_E_INVALID_PARAMETER;value->dwVersion=CARD_CAPABILITIES_CURRENT_VERSION;value->fCertificateCompression=FALSE;value->fKeyGen=FALSE;return 0;}
DWORD WINAPI freeSpace(PCARD_DATA d,DWORD flags,PCARD_FREE_SPACE_INFO value){if(!provider(d)||flags||!value)return SCARD_E_INVALID_PARAMETER;value->dwVersion=CARD_FREE_SPACE_INFO_CURRENT_VERSION;value->dwBytesAvailable=0;value->dwKeyContainersAvailable=0;value->dwMaxKeyContainers=1;return 0;}
DWORD WINAPI keySizes(PCARD_DATA d,DWORD spec,DWORD flags,PCARD_KEY_SIZES value){if(!provider(d)||flags||spec!=AT_SIGNATURE||!value)return SCARD_E_INVALID_PARAMETER;value->dwVersion=CARD_KEY_SIZES_CURRENT_VERSION;value->dwMinimumBitlen=value->dwMaximumBitlen=value->dwDefaultBitlen=2048;value->dwIncrementalBitlen=0;return 0;}
DWORD WINAPI enumFiles(PCARD_DATA d,LPSTR directory,LPSTR* out,PDWORD count,DWORD flags){
 if(!provider(d)||flags||!out||!count)return SCARD_E_INVALID_PARAMETER;*out=nullptr;*count=0;
 const char root[]="cardid\0cardcf\0cardapps\0",mscp[]="cmapfile\0ksc00\0";
 if(!directory||!*directory)return allocated(d,root,sizeof(root),reinterpret_cast<PBYTE*>(out),count);
 if(!strcmp(directory,"mscp"))return allocated(d,mscp,sizeof(mscp),reinterpret_cast<PBYTE*>(out),count);
 return SCARD_E_DIR_NOT_FOUND;
}
DWORD WINAPI fileInfo(PCARD_DATA d,LPSTR directory,LPSTR name,PCARD_FILE_INFO value){
 if(!provider(d)||!value)return SCARD_E_INVALID_PARAMETER;
 PBYTE bytes=nullptr;DWORD size=0;auto status=readFile(d,directory,name,0,&bytes,&size);
 if(status)return status;d->pfnCspFree(bytes);value->dwVersion=CARD_FILE_INFO_CURRENT_VERSION;value->cbFileSize=size;value->AccessCondition=EveryoneReadUserWriteAc;return 0;
}
DWORD WINAPI signData(PCARD_DATA d,PCARD_SIGNING_INFO info){auto result=boundary([&]()->DWORD{
 auto p=provider(d);if(!p||!info||info->bContainerIndex||info->dwKeySpec!=AT_SIGNATURE)return SCARD_E_INVALID_PARAMETER;
 info->pbSignedData=nullptr;info->cbSignedData=0;
 if(info->dwSigningFlags&~(CARD_PADDING_INFO_PRESENT|CARD_BUFFER_SIZE_ONLY|CARD_PADDING_PKCS1))return SCARD_E_INVALID_PARAMETER;
 if((info->dwSigningFlags&CARD_PADDING_PKCS1)&&(!(info->dwSigningFlags&CARD_PADDING_INFO_PRESENT)||info->dwPaddingType!=CARD_PADDING_PKCS1))return SCARD_E_UNSUPPORTED_FEATURE;
 unsigned algorithm=0;
 if(info->dwVersion==CARD_SIGNING_INFO_BASIC_VERSION||
    (info->dwVersion==CARD_SIGNING_INFO_CURRENT_VERSION&&!(info->dwSigningFlags&CARD_PADDING_INFO_PRESENT))){
  if(info->dwSigningFlags&CARD_PADDING_INFO_PRESENT)return SCARD_E_INVALID_PARAMETER;
  algorithm=info->aiHashAlg==CALG_SHA_256?1:info->aiHashAlg==CALG_SHA_384?2:info->aiHashAlg==CALG_SHA_512?3:0;
 }else if(info->dwVersion==CARD_SIGNING_INFO_CURRENT_VERSION){
  if(!(info->dwSigningFlags&CARD_PADDING_INFO_PRESENT)||info->dwPaddingType!=CARD_PADDING_PKCS1||!info->pPaddingInfo)return SCARD_E_UNSUPPORTED_FEATURE;
  auto padding=static_cast<BCRYPT_PKCS1_PADDING_INFO*>(info->pPaddingInfo);if(!padding->pszAlgId)return SCARD_E_UNSUPPORTED_FEATURE;
  algorithm=!wcscmp(padding->pszAlgId,BCRYPT_SHA256_ALGORITHM)?1:!wcscmp(padding->pszAlgId,BCRYPT_SHA384_ALGORITHM)?2:!wcscmp(padding->pszAlgId,BCRYPT_SHA512_ALGORITHM)?3:0;
 }else return ERROR_REVISION_MISMATCH;
 unsigned n=algorithm==1?32:algorithm==2?48:algorithm==3?64:0;if(!n)return SCARD_E_UNSUPPORTED_FEATURE;
 if(info->dwSigningFlags&CARD_BUFFER_SIZE_ONLY){info->cbSignedData=256;return 0;}
 if(!info->pbData||info->cbData!=n)return SCARD_E_INVALID_PARAMETER;
 if(!p->session||!p->authenticated)return SCARD_W_SECURITY_VIOLATION;
 uint8_t encoded[83]={0x30,0,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,1,0x65,3,4,2,0,5,0,4,0};encoded[1]=17+n;encoded[14]=static_cast<uint8_t>(algorithm);encoded[18]=n;memcpy(encoded+19,info->pbData,n);
 uint8_t signature[256];uint32_t size=sizeof(signature);auto s=p->sign(p->session,encoded,19+n,signature,&size);diagnostic("core.sign",static_cast<DWORD>(s));if(s){p->authenticated=false;return mapped(s);}
 // Cardmod uses little endian RSA signatures; CTK/core use big endian.
 std::reverse(signature,signature+size);return allocated(d,signature,size,&info->pbSignedData,&info->cbSignedData);
 });diagnostic("CardSignData",result,info?info->dwVersion:0,info?info->dwSigningFlags:0,info&&info->dwVersion==CARD_SIGNING_INFO_CURRENT_VERSION?info->dwPaddingType:0,info?info->aiHashAlg:0,info?info->dwKeySpec:0);return result;}
DWORD WINAPI containerInfo(PCARD_DATA d,BYTE index,DWORD flags,PCONTAINER_INFO info){return boundary([&]()->DWORD{
 auto p=provider(d);if(!p||index||flags||!info)return SCARD_E_INVALID_PARAMETER;
 auto s=p->readCertificate();if(s)return s;
 auto cert=CertCreateCertificateContext(X509_ASN_ENCODING,p->cert.data(),static_cast<DWORD>(p->cert.size()));if(!cert)return SCARD_E_INVALID_PARAMETER;
 struct Free{PCCERT_CONTEXT p;~Free(){CertFreeCertificateContext(p);}} free{cert};
 DWORD size=0;if(!CryptDecodeObject(X509_ASN_ENCODING,RSA_CSP_PUBLICKEYBLOB,cert->pCertInfo->SubjectPublicKeyInfo.PublicKey.pbData,cert->pCertInfo->SubjectPublicKeyInfo.PublicKey.cbData,0,nullptr,&size))return SCARD_F_INTERNAL_ERROR;
 PBYTE bytes=static_cast<PBYTE>(d->pfnCspAlloc(size));if(!bytes)return ERROR_NOT_ENOUGH_MEMORY;
 if(!CryptDecodeObject(X509_ASN_ENCODING,RSA_CSP_PUBLICKEYBLOB,cert->pCertInfo->SubjectPublicKeyInfo.PublicKey.pbData,cert->pCertInfo->SubjectPublicKeyInfo.PublicKey.cbData,0,bytes,&size)){d->pfnCspFree(bytes);return SCARD_F_INTERNAL_ERROR;}
 reinterpret_cast<BLOBHEADER*>(bytes)->aiKeyAlg=CALG_RSA_SIGN;*info={};info->dwVersion=CONTAINER_INFO_CURRENT_VERSION;info->pbSigPublicKey=bytes;info->cbSigPublicKey=size;return 0;
 });}
DWORD copied(const void* value,DWORD size,PBYTE out,DWORD capacity,PDWORD count){if(!count)return SCARD_E_INVALID_PARAMETER;*count=size;if(!out||capacity<size)return ERROR_INSUFFICIENT_BUFFER;memcpy(out,value,size);return 0;}
DWORD WINAPI property(PCARD_DATA d,LPCWSTR name,PBYTE out,DWORD capacity,PDWORD count,DWORD flags){
 if(!provider(d)||!name||!count)return SCARD_E_INVALID_PARAMETER;
 if(!wcscmp(name,CP_CARD_GUID)&&!flags)return copied(provider(d)->guid,16,out,capacity,count);
 DWORD value=0;BOOL yes=TRUE;
 if(!wcscmp(name,CP_CARD_READ_ONLY)&&!flags)return copied(&yes,sizeof(yes),out,capacity,count);
 if(!wcscmp(name,CP_CARD_CAPABILITIES)&&!flags){CARD_CAPABILITIES v{};v.dwVersion=CARD_CAPABILITIES_CURRENT_VERSION;return copied(&v,sizeof(v),out,capacity,count);}
 if(!wcscmp(name,CP_CARD_FREE_SPACE)&&!flags){CARD_FREE_SPACE_INFO v{};v.dwVersion=CARD_FREE_SPACE_INFO_CURRENT_VERSION;freeSpace(d,0,&v);return copied(&v,sizeof(v),out,capacity,count);}
 if(!wcscmp(name,CP_CARD_KEYSIZES)){CARD_KEY_SIZES v{};v.dwVersion=CARD_KEY_SIZES_CURRENT_VERSION;auto status=keySizes(d,flags,0,&v);return status?status:copied(&v,sizeof(v),out,capacity,count);}
 if(!wcscmp(name,CP_SUPPORTS_WIN_X509_ENROLLMENT)&&!flags){BOOL no=FALSE;return copied(&no,sizeof(no),out,capacity,count);}
 if(!wcscmp(name,CP_CARD_CACHE_MODE)&&!flags){value=CP_CACHE_MODE_NO_CACHE;return copied(&value,sizeof(value),out,capacity,count);}
 if(!wcscmp(name,CP_CARD_LIST_PINS)&&!flags){PIN_SET set=1<<ROLE_USER;return copied(&set,sizeof(set),out,capacity,count);}
 if(!wcscmp(name,CP_CARD_AUTHENTICATED_STATE)&&!flags){PIN_SET set=provider(d)->authenticated?(1<<ROLE_USER):0;return copied(&set,sizeof(set),out,capacity,count);}
 if(!wcscmp(name,CP_CARD_PIN_INFO)&&flags==ROLE_USER){PIN_INFO pin{};pin.dwVersion=PIN_INFO_CURRENT_VERSION;pin.PinType=AlphaNumericPinType;pin.PinPurpose=AuthenticationPin;pin.PinCachePolicy.dwVersion=PIN_CACHE_POLICY_CURRENT_VERSION;pin.PinCachePolicy.PinCachePolicyType=PinCacheTimed;pin.PinCachePolicy.dwPinCachePolicyInfo=websitePinCacheSeconds;return copied(&pin,sizeof(pin),out,capacity,count);}
 if(!wcscmp(name,CP_CARD_PIN_STRENGTH_VERIFY)&&flags==ROLE_USER){value=CARD_PIN_STRENGTH_PLAINTEXT;return copied(&value,sizeof(value),out,capacity,count);}
 if(!wcscmp(name,CP_PADDING_SCHEMES)&&flags==CARD_ASYMMETRIC_OPERATION){value=CARD_PADDING_PKCS1;return copied(&value,sizeof(value),out,capacity,count);}
 if(!wcscmp(name,CP_KEY_IMPORT_SUPPORT)&&!flags)return copied(&value,sizeof(value),out,capacity,count);
 if(!wcscmp(name,CP_ENUM_ALGORITHMS)&&flags==CARD_ASYMMETRIC_OPERATION){const wchar_t algorithms[]=L"RSA\0";return copied(algorithms,sizeof(algorithms),out,capacity,count);}
 return SCARD_E_UNSUPPORTED_FEATURE;
}
DWORD WINAPI containerProperty(PCARD_DATA d,BYTE index,LPCWSTR name,PBYTE out,DWORD size,PDWORD count,DWORD flags){
 if(index||flags||!name)return SCARD_E_INVALID_PARAMETER;
 if(!wcscmp(name,CCP_PIN_IDENTIFIER)){PIN_ID pin=ROLE_USER;return copied(&pin,sizeof(pin),out,size,count);}
 if(!wcscmp(name,CCP_CONTAINER_INFO)){if(!count)return SCARD_E_INVALID_PARAMETER;*count=sizeof(CONTAINER_INFO);if(!out||size<*count)return ERROR_INSUFFICIENT_BUFFER;auto info=reinterpret_cast<PCONTAINER_INFO>(out);info->dwVersion=CONTAINER_INFO_CURRENT_VERSION;return containerInfo(d,0,0,info);}
 return SCARD_E_UNSUPPORTED_FEATURE;
}
DWORD WINAPI setProperty(PCARD_DATA d,LPCWSTR name,PBYTE data,DWORD size,DWORD flags){
 if(!provider(d)||!name||flags||!data)return SCARD_E_INVALID_PARAMETER;
 // Presentation hints only; no authentication policy or PIN mutation writes.
 if(!wcscmp(name,CP_PARENT_WINDOW)&&size==sizeof(HWND))return 0;
 if(!wcscmp(name,CP_PIN_CONTEXT_STRING)&&size>=sizeof(wchar_t)&&size<=2048&&size%sizeof(wchar_t)==0&&reinterpret_cast<wchar_t*>(data)[size/sizeof(wchar_t)-1]==0)return 0;
 return SCARD_E_UNSUPPORTED_FEATURE;
}
}
#ifndef _MSC_VER
extern "C" __declspec(dllexport)
#endif
DWORD WINAPI CardAcquireContext(PCARD_DATA d,DWORD flags){return boundary([&]()->DWORD{
 if(!d||flags||!d->pwszCardName||!*d->pwszCardName||!d->pbAtr||!d->cbAtr||d->cbAtr>64||!d->hScard||!d->hSCardCtx||!d->pfnCspAlloc||!d->pfnCspReAlloc||!d->pfnCspFree||d->pvVendorSpecific)return SCARD_E_INVALID_PARAMETER;
 if(d->dwVersion<7)return ERROR_REVISION_MISMATCH;
 auto p=std::make_unique<Provider>(d);DWORD status=p->init();if(status)return status;
 d->dwVersion=7;d->pvVendorSpecific=p.release();
 d->pfnCardDeleteContext=removeContext;d->pfnCardReadFile=readFile;d->pfnCardSignData=signData;
 d->pfnCardAuthenticateEx=authenticate;d->pfnCardAuthenticatePin=authenticatePin;d->pfnCardDeauthenticateEx=deauthenticate;
 d->pfnCardGetContainerInfo=containerInfo;d->pfnCardGetContainerProperty=containerProperty;d->pfnCardGetProperty=property;
 d->pfnCardQueryCapabilities=capabilities;d->pfnCardQueryFreeSpace=freeSpace;d->pfnCardQueryKeySizes=keySizes;
 d->pfnCardGetFileInfo=fileInfo;d->pfnCardEnumFiles=enumFiles;d->pfnCardSetProperty=setProperty;
 UNSUPPORTED(pfnCardDeleteContainer);UNSUPPORTED(pfnCardCreateContainer);UNSUPPORTED(pfnCardGetChallenge);
 UNSUPPORTED(pfnCardAuthenticateChallenge);UNSUPPORTED(pfnCardUnblockPin);UNSUPPORTED(pfnCardChangeAuthenticator);
 UNSUPPORTED(pfnCardDeauthenticate);UNSUPPORTED(pfnCardCreateDirectory);UNSUPPORTED(pfnCardDeleteDirectory);
 UNSUPPORTED(pfnCardCreateFile);UNSUPPORTED(pfnCardWriteFile);UNSUPPORTED(pfnCardDeleteFile);UNSUPPORTED(pfnCardRSADecrypt);
 UNSUPPORTED(pfnCardConstructDHAgreement);UNSUPPORTED(pfnCardDeriveKey);UNSUPPORTED(pfnCardDestroyDHAgreement);
 UNSUPPORTED(pfnCardGetChallengeEx);UNSUPPORTED(pfnCardChangeAuthenticatorEx);UNSUPPORTED(pfnCardSetContainerProperty);
 UNSUPPORTED(pfnMDImportSessionKey);UNSUPPORTED(pfnMDEncryptData);UNSUPPORTED(pfnCardImportSessionKey);
 UNSUPPORTED(pfnCardGetSharedKeyHandle);UNSUPPORTED(pfnCardGetAlgorithmProperty);UNSUPPORTED(pfnCardGetKeyProperty);
 UNSUPPORTED(pfnCardSetKeyProperty);UNSUPPORTED(pfnCardDestroyKey);UNSUPPORTED(pfnCardProcessEncryptedData);UNSUPPORTED(pfnCardCreateContainerEx);
 d->pvUnused3=d->pvUnused4=nullptr;
 return SCARD_S_SUCCESS;
 });}
