// SPDX-License-Identifier: BSD-3-Clause
#include "local_cache.h"
#include "paired_store.h"
#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#else
#include <pwd.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#endif
namespace cie_cache {
namespace {
namespace fs=std::filesystem;
[[noreturn]] void failure(){
#ifdef _WIN32
 throw cie_pairing::StoreError(GetLastError());
#else
 throw cie_pairing::StoreError(errno?errno:EIO);
#endif
}
std::string name(const std::string& kind,const std::string& id){
 cie_pairing::checkId(id);if(kind!="card"&&kind!="web")throw std::runtime_error("pairing_invalid_record");return id+"."+kind;
}
std::string temporary(){uint8_t bytes[16];random(bytes,sizeof(bytes));std::string s=".tmp-";const char h[]="0123456789abcdef";for(auto b:bytes){s+=h[b>>4];s+=h[b&15];}return s;}
fs::path location(){
#ifdef CIE_PAIRING_TEST_SERVICE
#ifdef _WIN32
 wchar_t test[32768]{};auto n=GetEnvironmentVariableW(L"CIE_PAIRING_TEST_CACHE",test,32768);
 if(!n||n>=32768||!fs::path(test).is_absolute())throw std::runtime_error("pairing_store_unavailable");
 return fs::canonical(fs::path(test))/"cache-v3";
#else
 const char* test=std::getenv("CIE_PAIRING_TEST_CACHE");
 if(!test||!*test||!fs::u8path(test).is_absolute())throw std::runtime_error("pairing_store_unavailable");
 return fs::canonical(fs::u8path(test))/"cache-v3";
#endif
#else
#ifdef _WIN32
 wchar_t base[32768]{};auto n=GetEnvironmentVariableW(L"LOCALAPPDATA",base,32768);
 if(!n||n>=32768)throw std::runtime_error("pairing_store_unavailable");
 return fs::path(base)/cie_pairing::service/"cache-v3";
#else
 struct passwd user{},*found=nullptr;char buffer[32768];
 if(getpwuid_r(getuid(),&user,buffer,sizeof(buffer),&found)||!found||!user.pw_dir)throw std::runtime_error("pairing_store_unavailable");
#ifdef __APPLE__
 return fs::path(user.pw_dir)/"Library/Application Support"/cie_pairing::service/"cache-v3";
#else
 return fs::path(user.pw_dir)/".local/share"/cie_pairing::service/"cache-v3";
#endif
#endif
#endif
}
#ifdef _WIN32
struct Handle {HANDLE h=INVALID_HANDLE_VALUE;~Handle(){if(h!=INVALID_HANDLE_VALUE)CloseHandle(h);}operator HANDLE()const{return h;}};
struct PrivateAccess {
 std::vector<uint8_t> token;PSECURITY_DESCRIPTOR descriptor=nullptr;PSID user=nullptr;SECURITY_ATTRIBUTES attributes{};
 PrivateAccess(){Handle handle;if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&handle.h))failure();DWORD n=0;
  GetTokenInformation(handle,TokenUser,nullptr,0,&n);token.resize(n);if(!GetTokenInformation(handle,TokenUser,token.data(),n,&n))failure();user=((TOKEN_USER*)token.data())->User.Sid;
  LPWSTR text=nullptr;if(!ConvertSidToStringSidW(user,&text))failure();std::wstring sid=text;LocalFree(text);
  auto sddl=L"O:"+sid+L"D:P(A;;FA;;;"+sid+L")";
  if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(),SDDL_REVISION_1,&descriptor,nullptr))failure();
  attributes={sizeof(attributes),descriptor,FALSE};
 }
 ~PrivateAccess(){if(descriptor)LocalFree(descriptor);}
 void validate(HANDLE file,bool directory){
  BY_HANDLE_FILE_INFORMATION info{};if(!GetFileInformationByHandle(file,&info))failure();
  if((info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)||bool(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)!=directory||(!directory&&info.nNumberOfLinks!=1))throw std::runtime_error("pairing_cache_permissions");
  PSID owner=nullptr;PACL acl=nullptr;PSECURITY_DESCRIPTOR security=nullptr;
  auto result=GetSecurityInfo(file,SE_FILE_OBJECT,OWNER_SECURITY_INFORMATION|DACL_SECURITY_INFORMATION,&owner,nullptr,&acl,nullptr,&security);
  if(result){SetLastError(result);failure();}struct Free{PSECURITY_DESCRIPTOR p;~Free(){LocalFree(p);}} free{security};
  SECURITY_DESCRIPTOR_CONTROL control=0;DWORD revision=0;
  if(!owner||!EqualSid(owner,user)||!acl||!GetSecurityDescriptorControl(security,&control,&revision)||!(control&SE_DACL_PROTECTED))throw std::runtime_error("pairing_cache_permissions");
  bool ownerAllowed=false;for(DWORD i=0;i<acl->AceCount;++i){void* raw=nullptr;if(!GetAce(acl,i,&raw))failure();auto header=(ACE_HEADER*)raw;
   if(header->AceType!=ACCESS_ALLOWED_ACE_TYPE)throw std::runtime_error("pairing_cache_permissions");auto ace=(ACCESS_ALLOWED_ACE*)raw;
   if(!EqualSid(&ace->SidStart,user))throw std::runtime_error("pairing_cache_permissions");if(ace->Mask&FILE_READ_DATA)ownerAllowed=true;
  }if(!ownerAllowed)throw std::runtime_error("pairing_cache_permissions");
 }
};
#else
struct Handle {int h=-1;~Handle(){if(h>=0)close(h);}operator int()const{return h;}};
void validate(int fd,bool directory){struct stat s{};if(fstat(fd,&s))failure();
 if((directory?!S_ISDIR(s.st_mode):!S_ISREG(s.st_mode))||s.st_uid!=getuid()||(s.st_mode&0077)||(!directory&&s.st_nlink!=1))throw std::runtime_error("pairing_cache_permissions");
}
#endif
}
struct Store::Impl {
 fs::path path;bool present=false;
#ifdef _WIN32
 PrivateAccess access;Handle directory,lock;
#else
 Handle directory,lock;
#endif
 explicit Impl(bool create):path(location()){
#ifdef _WIN32
  // Reject reparse points in all existing path components. The leaf directory
  // and every file have an explicit, protected current-user-only DACL.
  auto current=path.root_path();for(const auto& part:path.relative_path()){
   current/=part;auto attributes=GetFileAttributesW(current.c_str());
   if(attributes==INVALID_FILE_ATTRIBUTES){if(GetLastError()!=ERROR_FILE_NOT_FOUND&&GetLastError()!=ERROR_PATH_NOT_FOUND)failure();if(!create)return;
    if(!CreateDirectoryW(current.c_str(),current==path?&access.attributes:nullptr)&&GetLastError()!=ERROR_ALREADY_EXISTS)failure();
   }else if((attributes&FILE_ATTRIBUTE_REPARSE_POINT)||!(attributes&FILE_ATTRIBUTE_DIRECTORY))throw std::runtime_error("pairing_cache_permissions");
  }
  directory.h=CreateFileW(path.c_str(),READ_CONTROL|FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  if(directory.h==INVALID_HANDLE_VALUE)failure();access.validate(directory,true);
  auto p=path/L".lock";lock.h=CreateFileW(p.c_str(),GENERIC_READ|GENERIC_WRITE|READ_CONTROL,FILE_SHARE_READ|FILE_SHARE_WRITE,&access.attributes,OPEN_ALWAYS,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  if(lock.h==INVALID_HANDLE_VALUE)failure();access.validate(lock,false);OVERLAPPED overlap{};
  if(!LockFileEx(lock,LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY,0,1,0,&overlap))failure();
#else
  // Walk directory handles without following symlinks, including ancestors.
  Handle parent;parent.h=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC);if(parent.h<0)failure();
  auto relative=path.relative_path();for(auto it=relative.begin();it!=relative.end();++it){auto component=it->string();if(component=="."||component=="..")throw std::runtime_error("pairing_cache_permissions");
   int next=openat(parent,component.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
   if(next<0&&errno==ENOENT){if(!create)return;if(mkdirat(parent,component.c_str(),0700)&&errno!=EEXIST)failure();next=openat(parent,component.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);}
   if(next<0)failure();close(parent.h);parent.h=next;
  }
  validate(parent,true);directory.h=parent.h;parent.h=-1;
  lock.h=openat(directory,".lock",O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0600);if(lock.h<0)failure();validate(lock,false);
  if(flock(lock,LOCK_EX|LOCK_NB))failure();
#endif
  present=true;
 }
 Bytes rawRead(const std::string& filename){if(!present)return {};
#ifdef _WIN32
  Handle file;auto p=path/fs::u8path(filename);file.h=CreateFileW(p.c_str(),GENERIC_READ|READ_CONTROL,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  if(file.h==INVALID_HANDLE_VALUE){if(GetLastError()==ERROR_FILE_NOT_FOUND)return {};failure();}access.validate(file,false);
  LARGE_INTEGER length;if(!GetFileSizeEx(file,&length))failure();if(length.QuadPart<=0||length.QuadPart>11000)throw std::runtime_error("pairing_cache_invalid");
  Bytes data((size_t)length.QuadPart);DWORD done=0;if(!ReadFile(file,data.data(),(DWORD)data.size(),&done,nullptr)||done!=data.size())failure();return data;
#else
  Handle file;file.h=openat(directory,filename.c_str(),O_RDONLY|O_NOFOLLOW|O_CLOEXEC);if(file.h<0){if(errno==ENOENT)return {};failure();}validate(file,false);
  struct stat s{};if(fstat(file,&s))failure();if(s.st_size<=0||s.st_size>11000)throw std::runtime_error("pairing_cache_invalid");Bytes data((size_t)s.st_size);size_t n=0;
  while(n<data.size()){auto count=::read(file,data.data()+n,data.size()-n);if(count<0&&errno==EINTR)continue;if(count<=0)failure();n+=(size_t)count;}return data;
#endif
 }
 void rawErase(const std::string& filename){if(!present)return;
#ifdef _WIN32
  auto p=path/fs::u8path(filename);auto attributes=GetFileAttributesW(p.c_str());if(attributes==INVALID_FILE_ATTRIBUTES){if(GetLastError()==ERROR_FILE_NOT_FOUND)return;failure();}
  if((attributes&FILE_ATTRIBUTE_REPARSE_POINT)||(attributes&FILE_ATTRIBUTE_DIRECTORY))throw std::runtime_error("pairing_cache_permissions");
  if(!DeleteFileW(p.c_str()))failure();
#else
  struct stat s{};if(fstatat(directory,filename.c_str(),&s,AT_SYMLINK_NOFOLLOW)){if(errno==ENOENT)return;failure();}
  if(!S_ISREG(s.st_mode)||s.st_uid!=getuid()||s.st_nlink!=1)throw std::runtime_error("pairing_cache_permissions");
  if(unlinkat(directory,filename.c_str(),0)||fsync(directory))failure();
#endif
 }
 bool rawWrite(const std::string& filename,const Bytes& bytes,bool replace=true){if(!present)throw std::runtime_error("pairing_store_unavailable");auto temp=temporary();
  try{
#ifdef _WIN32
   auto from=path/fs::u8path(temp),to=path/fs::u8path(filename);
   {Handle file;file.h=CreateFileW(from.c_str(),GENERIC_WRITE|READ_CONTROL,0,&access.attributes,CREATE_NEW,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);if(file.h==INVALID_HANDLE_VALUE)failure();access.validate(file,false);
    DWORD n=0;if(!WriteFile(file,bytes.data(),(DWORD)bytes.size(),&n,nullptr)||n!=bytes.size()||!FlushFileBuffers(file))failure();}
   if(!MoveFileExW(from.c_str(),to.c_str(),MOVEFILE_WRITE_THROUGH|(replace?MOVEFILE_REPLACE_EXISTING:0))){if(!replace&&(GetLastError()==ERROR_ALREADY_EXISTS||GetLastError()==ERROR_FILE_EXISTS)){DeleteFileW(from.c_str());return false;}failure();}
#else
   {Handle file;file.h=openat(directory,temp.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(file.h<0)failure();validate(file,false);size_t n=0;
    while(n<bytes.size()){auto count=::write(file,bytes.data()+n,bytes.size()-n);if(count<0&&errno==EINTR)continue;if(count<=0)failure();n+=(size_t)count;}if(fsync(file))failure();}
   if(replace){if(renameat(directory,temp.c_str(),directory,filename.c_str()))failure();}
   else {if(linkat(directory,temp.c_str(),directory,filename.c_str(),0)){if(errno==EEXIST){unlinkat(directory,temp.c_str(),0);return false;}failure();}if(unlinkat(directory,temp.c_str(),0))failure();}
   if(fsync(directory))failure();
#endif
   return true;
  }catch(...){
#ifdef _WIN32
   DeleteFileW((path/fs::u8path(temp)).c_str());
#else
   unlinkat(directory,temp.c_str(),0);
#endif
   throw;
  }
 }
 std::vector<std::string> ids(const std::string& kind){name(kind,"VALID");std::vector<std::string> out;if(!present)return out;auto suffix="."+kind;
  for(auto& entry:fs::directory_iterator(path)){auto s=entry.path().filename().u8string();if(s.size()<=suffix.size()||s.compare(s.size()-suffix.size(),suffix.size(),suffix))continue;
   auto id=s.substr(0,s.size()-suffix.size());cie_pairing::checkId(id);
   // Directory traversal never opens or decrypts the candidate file.
   auto status=entry.symlink_status();if(!fs::is_regular_file(status))throw std::runtime_error("pairing_cache_permissions");out.push_back(id);
   if(out.size()>256)throw std::runtime_error("pairing_limit");}
  std::sort(out.begin(),out.end());return out;
 }
 Bytes key(bool create){auto bytes=rawRead(".key");if(!bytes.empty()){if(bytes.size()!=64)throw std::runtime_error("pairing_cache_invalid");return bytes;}
  if(!create)throw std::runtime_error("pairing_cache_key_missing");
  if(!ids("card").empty()||!ids("web").empty())throw std::runtime_error("pairing_cache_key_missing");
  Bytes generated(64);random(generated.data(),generated.size());rawWrite(".key",generated,false);
  auto saved=rawRead(".key");if(saved.size()!=64)throw std::runtime_error("pairing_cache_invalid");return saved;
 }
};
Store::Store(bool create):impl_(new Impl(create)){}
Store::~Store(){delete impl_;}
void Store::prepare(){(void)impl_->key(true);}
Bytes Store::read(const std::string& kind,const std::string& id){auto encoded=impl_->rawRead(name(kind,id));if(encoded.empty())return {};auto key=impl_->key(false);return decrypt(key,std::string(cie_pairing::service)+"/cache-v3/"+kind+"/"+id,encoded);}
void Store::write(const std::string& kind,const std::string& id,const Bytes& bytes){auto filename=name(kind,id);auto key=impl_->key(true);auto encoded=encrypt(key,std::string(cie_pairing::service)+"/cache-v3/"+kind+"/"+id,bytes);impl_->rawWrite(filename,encoded);}
void Store::erase(const std::string& kind,const std::string& id){impl_->rawErase(name(kind,id));}
std::vector<std::string> Store::list(const std::string& kind){return impl_->ids(kind);}
}
