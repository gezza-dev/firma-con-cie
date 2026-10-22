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
#include "setup_registry.h"
#include "package_status.h"
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
struct Card {SCARDCONTEXT context=0;SCARDHANDLE card=0;DWORD protocol=0;BYTE atr[64]{};DWORD atrSize=64;
 ~Card(){if(card)SCardDisconnect(card,SCARD_LEAVE_CARD);if(context)SCardReleaseContext(context);}
 void connect(const std::wstring& reader){if(SCardEstablishContext(SCARD_SCOPE_SYSTEM,nullptr,nullptr,&context)||SCardConnectW(context,reader.c_str(),SCARD_SHARE_SHARED,SCARD_PROTOCOL_T1,&card,&protocol))throw 4;
 wchar_t name[4096];DWORD length=4096,state=0;if(SCardStatusW(card,name,&length,&state,&protocol,atr,&atrSize)||!atrSize||atrSize>64)throw 5;}

};
using Guards=std::vector<std::unique_ptr<Handle>>;
Guards installFiles(const fs::path& source,const fs::path& root,const fs::path& target){
 Guards guards;
 for(const auto& path:{root.parent_path(),root,target,target/L"backend"})guards.push_back(secureDirectory(path));
 // Keep previous versions intact: browser processes may still have them loaded.
 for(const auto& entry:cie_setup_payload::files){auto destination=target/entry.path;
  fs::path parent=target;for(const auto& part:fs::path(entry.path).parent_path()){parent/=part;guards.push_back(secureDirectory(parent));}
  if(fs::exists(destination)){if(hashFile(destination,entry.size)!=entry.sha256)throw 9;}
  else if(!CopyFileW((source/entry.path).c_str(),destination.c_str(),TRUE))throw 7;
  guards.push_back(secureDirectory(destination,false));
 }
 validate(target);return guards;
}
int checkSetup(const std::wstring& reader){
 const fs::path source(executableDirectory());validate(source);
 Card card;card.connect(reader);auto names=matching(card.context,card.atr);
 if(cie_setup::foreignMatch(names))return 3;
 const auto root=installationRoot(),target=root/cie_setup_payload::version;
 for(const auto& n:names)if(!ownedModule(provider(card.context,n,0x80000001),root)||provider(card.context,n,3)!=MS_SMART_CARD_KEY_STORAGE_PROVIDER)return 3;
 if(names.empty())return 10;
 for(const auto& n:names)if(fs::path(provider(card.context,n,0x80000001))!=target/L"cie_prototype_minidriver.dll"||provider(card.context,n,SCARD_PROVIDER_CSP)!=MS_SCARD_PROV_W)return 10;
 try{validate(target);return 0;}catch(...){return 9;}
}
cie_setup::RegistryStore cardDatabase(){return {HKEY_LOCAL_MACHINE,L"SOFTWARE\\Microsoft\\Cryptography\\Calais\\SmartCards"};}
int packageStatus(){
 validate(executableDirectory());
 const auto root=installationRoot(),target=root/cie_setup_payload::version;
 return cie_setup::packageStatus(cardDatabase().read(),(target/L"cie_prototype_minidriver.dll").wstring(),
  [&](const auto& module){return ownedModule(module,root);},
  [&]{try{validate(target);return true;}catch(...){return false;}});
}
// Only the package installer writes this fixed machine database. No PC/SC
// context or card operation occurs, including on PCs with no reader/service.
int installPackage(bool planOnly=false){
 const fs::path source(executableDirectory());validate(source);if(!planOnly&&!elevated())return 2;
 const auto root=installationRoot(),target=root/cie_setup_payload::version;
 auto store=cardDatabase();const auto plan=cie_setup::planCatalog(store.read(),(target/L"cie_prototype_minidriver.dll").wstring(),[&](const auto& path){return ownedModule(path,root);});
 if(plan.code||planOnly)return plan.code;
 auto guards=installFiles(source,root,target);
 return cie_setup::applyCatalog(store,plan);
}
int unregisterPackage(){
 if(!elevated())return 2;
 auto store=cardDatabase();const auto root=installationRoot();const auto before=store.read();
 // Validate ownership of every key before any removal; rollback the complete
 // owned set if deletion fails. User certificates/caches are never consulted.
 cie_setup::CatalogPlan plan;
 // Foreign middleware may have been installed later. It must not prevent the
 // removal of our own registrations, and it must never be changed.
 for(const auto& item:before)if(cie_setup::ownedName(item.first)){
  const auto& v=item.second;
  if(!ownedModule(cie_setup::stringValue(v,L"80000001"),root)||cie_setup::stringValue(v,L"Crypto Provider")!=MS_SCARD_PROV_W||cie_setup::stringValue(v,L"Smart Card Key Storage Provider")!=MS_SMART_CARD_KEY_STORAGE_PROVIDER)return 3;
 }
 plan.code=0;plan.before=before;plan.after.clear();return cie_setup::applyCatalog(store,plan);
}
}
int wmain(int argc,wchar_t** argv){
 SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32);
 try{
  if(argc==2&&!wcscmp(argv[1],L"--validate-package")){validate(executableDirectory());return 0;}
  if(argc==2&&!wcscmp(argv[1],L"--status-package"))return packageStatus();
  if(argc==2&&!wcscmp(argv[1],L"--install-package"))return installPackage();
  if(argc==2&&!wcscmp(argv[1],L"--plan-package"))return installPackage(true);
  if(argc==2&&!wcscmp(argv[1],L"--unregister-package"))return unregisterPackage();
  if(argc!=3||!cie_setup::validReader(argv[2])||wcscmp(argv[1],L"--check"))return 6;
  return checkSetup(argv[2]);
 }catch(int code){return code;}catch(...){return 7;}
}
