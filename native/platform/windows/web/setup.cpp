// SPDX-License-Identifier: BSD-3-Clause
// Elevated helper: fixed hash-pinned payload, public discovery only, no credentials.
#include <windows.h>
#include <winscard.h>
#include <wincrypt.h>
#include <ncrypt.h>
#include <shlobj.h>
#include <aclapi.h>
#include <sddl.h>
#include <bcrypt.h>
#include <filesystem>
#include <fstream>
#include <array>
#include <memory>
#include "setup_policy.h"
#include "card_identification.h"
#include "cie_web.h"
#include "setup_payload.h"
namespace fs=std::filesystem;
using cie_setup::Code;
namespace {
struct Handle {HANDLE h=INVALID_HANDLE_VALUE;~Handle(){if(h&&h!=INVALID_HANDLE_VALUE)CloseHandle(h);} Handle()=default;Handle(const Handle&)=delete;};
std::wstring executableDirectory(){wchar_t p[32768];auto n=GetModuleFileNameW(nullptr,p,32768);if(!n||n>=32768)throw 6;return fs::path(p).parent_path().wstring();}
std::string hashFile(const fs::path& path,uint64_t expectedSize){
 if(GetFileAttributesW(path.c_str())&FILE_ATTRIBUTE_REPARSE_POINT)throw 6;
 Handle file;file.h=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);if(file.h==INVALID_HANDLE_VALUE)throw 6;
 BY_HANDLE_FILE_INFORMATION info{};if(!GetFileInformationByHandle(file.h,&info)||(info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)))throw 6;
 if((uint64_t(info.nFileSizeHigh)<<32|info.nFileSizeLow)!=expectedSize)throw 6;
 BCRYPT_ALG_HANDLE alg=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;
 if(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0))throw 6;
 struct Free{BCRYPT_ALG_HANDLE& a;BCRYPT_HASH_HANDLE& h;~Free(){if(h)BCryptDestroyHash(h);if(a)BCryptCloseAlgorithmProvider(a,0);}} free{alg,hash};
 if(BCryptCreateHash(alg,&hash,nullptr,0,nullptr,0,0))throw 6;
 std::array<BYTE,65536> data{};DWORD n=0;
 for(;;){if(!ReadFile(file.h,data.data(),static_cast<DWORD>(data.size()),&n,nullptr))throw 6;if(!n)break;if(BCryptHashData(hash,data.data(),n,0))throw 6;}
 BYTE digest[32];if(BCryptFinishHash(hash,digest,32,0))throw 6;
 const char hex[]="0123456789abcdef";std::string out;for(auto b:digest){out+=hex[b>>4];out+=hex[b&15];}return out;
}
void validate(const fs::path& root){
 for(const auto& entry:cie_setup_payload::files){
  auto path=root/entry.path;for(auto parent=path.parent_path();parent!=root.parent_path();parent=parent.parent_path()){
   auto attrs=GetFileAttributesW(parent.c_str());if(attrs==INVALID_FILE_ATTRIBUTES||(attrs&FILE_ATTRIBUTE_REPARSE_POINT))throw 6;
   if(parent==root)break;
  }
  if(hashFile(path,entry.size)!=entry.sha256)throw 6;
 }
}
bool elevated(){Handle h;h.h=nullptr;if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&h.h))return false;TOKEN_ELEVATION e{};DWORD size=0;return GetTokenInformation(h.h,TokenElevation,&e,sizeof(e),&size)&&e.TokenIsElevated;}
fs::path installationRoot(){PWSTR value=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_ProgramFiles,0,nullptr,&value)))throw 7;fs::path p(value);CoTaskMemFree(value);return p/L"CIE ID Flutter Prototype"/L"WebToken";}
// Keep opened directory handles without FILE_SHARE_DELETE until installation ends.
std::unique_ptr<Handle> secureDirectory(const fs::path& path,bool directory=true){
 PSECURITY_DESCRIPTOR sd=nullptr;if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;GRGX;;;BU)",SDDL_REVISION_1,&sd,nullptr))throw 7;
 struct Free{PSECURITY_DESCRIPTOR p;~Free(){LocalFree(p);}} free{sd};
 SECURITY_ATTRIBUTES sa{sizeof(sa),sd,FALSE};if(directory&&!CreateDirectoryW(path.c_str(),&sa)&&GetLastError()!=ERROR_ALREADY_EXISTS)throw 7;
 auto h=std::make_unique<Handle>();h->h=CreateFileW(path.c_str(),READ_CONTROL|WRITE_DAC|WRITE_OWNER|(directory?FILE_LIST_DIRECTORY:GENERIC_READ),directory?(FILE_SHARE_READ|FILE_SHARE_WRITE):FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);if(h->h==INVALID_HANDLE_VALUE)throw 7;
 BY_HANDLE_FILE_INFORMATION info{};if(!GetFileInformationByHandle(h->h,&info)||(info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)||bool(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)!=directory||(!directory&&info.nNumberOfLinks!=1))throw 7;
 BOOL present=FALSE,defaulted=FALSE;PACL acl=nullptr;PSID owner=nullptr;GetSecurityDescriptorDacl(sd,&present,&acl,&defaulted);GetSecurityDescriptorOwner(sd,&owner,&defaulted);
 if(SetSecurityInfo(h->h,SE_FILE_OBJECT,OWNER_SECURITY_INFORMATION|DACL_SECURITY_INFORMATION|PROTECTED_DACL_SECURITY_INFORMATION,owner,nullptr,acl,nullptr)!=ERROR_SUCCESS)throw 7;
 return h;
}
std::wstring provider(SCARDCONTEXT c,const std::wstring& name,DWORD type){wchar_t text[32768]{};DWORD n=32768;return SCardGetCardTypeProviderNameW(c,name.c_str(),type,text,&n)==SCARD_S_SUCCESS?text:L"";}
std::vector<std::wstring> matching(SCARDCONTEXT c,const BYTE* atr){
 DWORD count=0;auto status=SCardListCardsW(c,atr,nullptr,0,nullptr,&count);if(status==SCARD_E_UNKNOWN_CARD)return {};if(status!=SCARD_S_SUCCESS||count>65536)throw 8;
 std::vector<wchar_t> names(count?count:2);if(count&&SCardListCardsW(c,atr,nullptr,0,names.data(),&count))throw 8;
 std::vector<std::wstring> out;for(auto p=names.data();*p;p+=wcslen(p)+1)out.emplace_back(p);return out;
}
bool ownedModule(const std::wstring& text,const fs::path& root){
 auto path=fs::path(text).lexically_normal();if(!path.is_absolute()||path.filename()!=L"cie_prototype_minidriver.dll")return false;
 auto relative=path.lexically_relative(root);return !relative.empty()&&*relative.begin()!=L"..";
}
struct Card {SCARDCONTEXT context=0;SCARDHANDLE card=0;bool locked=false;DWORD protocol=0;BYTE atr[64]{};DWORD atrSize=64;cie_identification::ReadCommands commands;
 ~Card(){if(locked)SCardEndTransaction(card,SCARD_LEAVE_CARD);if(card)SCardDisconnect(card,SCARD_LEAVE_CARD);if(context)SCardReleaseContext(context);}
 void connect(const std::wstring& reader){if(SCardEstablishContext(SCARD_SCOPE_SYSTEM,nullptr,nullptr,&context)||SCardConnectW(context,reader.c_str(),SCARD_SHARE_SHARED,SCARD_PROTOCOL_T1,&card,&protocol))throw 4;
 wchar_t name[4096];DWORD length=4096,state=0;if(SCardStatusW(card,name,&length,&state,&protocol,atr,&atrSize)||!atrSize||atrSize>64)throw 5;}
 static int32_t transmit(void* ctx,const uint8_t* bytes,uint32_t size,uint8_t* out,uint32_t* length){auto& s=*static_cast<Card*>(ctx);if(!s.commands.accept(bytes,size))return CIE_WEB_TRANSPORT;DWORD n=*length;auto result=SCardTransmit(s.card,SCARD_PCI_T1,bytes,size,nullptr,out,&n);*length=n;return result?CIE_WEB_TRANSPORT:0;}
};
void discover(Card& card,const fs::path& folder){
 if(SCardBeginTransaction(card.card))throw 5;card.locked=true;
 auto module=LoadLibraryExW((folder/L"backend"/L"cie_web.dll").c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);if(!module)throw 6;
 struct Free{HMODULE h;~Free(){FreeLibrary(h);}} free{module};
 auto open=reinterpret_cast<decltype(&cie_web_open)>(GetProcAddress(module,"cie_web_open"));auto close=reinterpret_cast<decltype(&cie_web_close)>(GetProcAddress(module,"cie_web_close"));auto version=reinterpret_cast<decltype(&cie_web_abi_version)>(GetProcAddress(module,"cie_web_abi_version"));
 if(!open||!close||!version||version()!=1)throw 6;
 CieWebSession* session=nullptr;auto status=open(card.atr,card.atrSize,Card::transmit,&card,nullptr,&session);if(session)close(session);if(status)throw 5;
 SCardEndTransaction(card.card,SCARD_LEAVE_CARD);card.locked=false;
}
int setup(bool install,const std::wstring& reader){
 const fs::path source(executableDirectory());validate(source);if(install&&!elevated())return 2;
 Card card;card.connect(reader);auto names=matching(card.context,card.atr);if(cie_setup::foreignMatch(names)||names.size()>1)return 3;
 const auto root=installationRoot();const auto target=root/cie_setup_payload::version;
 for(const auto& n:names)if(!ownedModule(provider(card.context,n,0x80000001),root)||provider(card.context,n,3)!=MS_SMART_CARD_KEY_STORAGE_PROVIDER)return 3;
 bool current=!names.empty();for(const auto& n:names)current=current&&fs::path(provider(card.context,n,0x80000001))==target/L"cie_prototype_minidriver.dll"&&provider(card.context,n,SCARD_PROVIDER_CSP)==MS_SCARD_PROV_W;
 if(current){try{validate(target);return 0;}catch(...){return 9;}}
 if(!install)return 10;
 std::vector<std::unique_ptr<Handle>> guards;
 for(const auto& path:{root.parent_path(),root,target,target/L"backend"})guards.push_back(secureDirectory(path));
 // Never replace loaded binaries. Version directories are immutable and hash-bound.
 for(const auto& entry:cie_setup_payload::files){auto destination=target/entry.path;
  fs::path parent=target;for(const auto& part:fs::path(entry.path).parent_path()){parent/=part;guards.push_back(secureDirectory(parent));}
  if(fs::exists(destination)){if(hashFile(destination,entry.size)!=entry.sha256)throw 9;}
  else if(!CopyFileW((source/entry.path).c_str(),destination.c_str(),TRUE))throw 7;
  guards.push_back(secureDirectory(destination,false));
 }
 validate(target);discover(card,target);
 std::wstring name;if(names.empty()){
  name=cie_setup::cardName;
  auto all=matching(card.context,nullptr);
  if(std::find(all.begin(),all.end(),name)!=all.end()){name+=L" ";const char hex[]="0123456789abcdef";BYTE hash[32];DWORD n=32;if(!CryptHashCertificate(0,CALG_SHA_256,0,card.atr,card.atrSize,hash,&n))throw 8;for(unsigned i=0;i<8;++i){name+=hex[hash[i]>>4];name+=hex[hash[i]&15];}}
  if(std::find(all.begin(),all.end(),name)!=all.end())return 3;
 }else name=names.front();
 // Refuse races: another registration may have appeared during public discovery.
 auto again=matching(card.context,card.atr);if(cie_setup::foreignMatch(again)||again!=names)return 3;
 bool created=names.empty();std::wstring oldCsp,oldKsp,oldModule;
 if(created){std::vector<BYTE> mask(card.atrSize,0xff);if(SCardIntroduceCardTypeW(card.context,name.c_str(),nullptr,nullptr,0,card.atr,mask.data(),card.atrSize))return 8;}
 else {oldCsp=provider(card.context,name,SCARD_PROVIDER_CSP);oldKsp=provider(card.context,name,3);oldModule=provider(card.context,name,0x80000001);}
 auto set=[&](DWORD type,const std::wstring& value){return SCardSetCardTypeProviderNameW(card.context,name.c_str(),type,value.c_str());};
 auto module=(target/L"cie_prototype_minidriver.dll").wstring();
 return cie_setup::publishBindings(created,set,[&]{return SCardForgetCardTypeW(card.context,name.c_str())==SCARD_S_SUCCESS;},
  [&]{return provider(card.context,name,0x80000001)==module&&provider(card.context,name,3)==MS_SMART_CARD_KEY_STORAGE_PROVIDER&&provider(card.context,name,SCARD_PROVIDER_CSP)==MS_SCARD_PROV_W;},oldCsp,oldKsp,oldModule,module);
}
}
int wmain(int argc,wchar_t** argv){
 SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32);
 try{
  if(argc==2&&!wcscmp(argv[1],L"--validate-package")){validate(executableDirectory());return 0;}
  if(argc!=3||(!cie_setup::validReader(argv[2]))||(wcscmp(argv[1],L"--check")&&wcscmp(argv[1],L"--install")))return 6;
  return setup(!wcscmp(argv[1],L"--install"),argv[2]);
 }catch(int code){return code;}catch(...){return 7;}
}
