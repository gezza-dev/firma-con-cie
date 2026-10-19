// SPDX-License-Identifier: BSD-3-Clause
#include "paired_store.h"
#include <filesystem>
#include <cstdlib>
#ifdef _WIN32
#include <windows.h>
#else
#include <pwd.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#endif
namespace cie_pairing {
namespace {
namespace fs=std::filesystem;
fs::path root(){
#ifdef CIE_PAIRING_TEST_STATE
#ifdef _WIN32
 wchar_t test[32768]{};auto count=GetEnvironmentVariableW(L"CIE_PAIRING_TEST_STATE",test,32768);
 if(!count||count>=32768)throw std::runtime_error("pairing_invalidation_unavailable");
 return fs::weakly_canonical(fs::path(test));
#else
 const char* test=std::getenv("CIE_PAIRING_TEST_STATE");
 if(!test||!*test)throw std::runtime_error("pairing_invalidation_unavailable");
 return fs::weakly_canonical(fs::u8path(test));
#endif
#else
#ifdef _WIN32
 wchar_t base[32768]{};auto n=GetEnvironmentVariableW(L"LOCALAPPDATA",base,32768);
 if(!n||n>=32768)throw std::runtime_error("pairing_invalidation_unavailable");
 return fs::path(base)/service/"invalidated-v1";
#else
 auto user=getpwuid(getuid());
 if(!user||!user->pw_dir)throw std::runtime_error("pairing_invalidation_unavailable");
#ifdef __APPLE__
 return fs::path(user->pw_dir)/"Library/Application Support"/service/"invalidated-v1";
#else
 return fs::path(user->pw_dir)/".local/share"/service/"invalidated-v1";
#endif
#endif
#endif
}
bool markerExists(const fs::path& p){
 auto s=fs::symlink_status(p);return s.type()!=fs::file_type::not_found;
}
void ensureRoot(const fs::path& p){
 fs::create_directories(p);
 // Reject redirected state. This directory contains only nonsecret revocation markers.
 for(const auto& current:{p,p.parent_path()})
  if(fs::is_symlink(fs::symlink_status(current)))throw std::runtime_error("pairing_invalidation_unavailable");
#ifndef _WIN32
 if(chmod(p.c_str(),0700))throw std::runtime_error("pairing_invalidation_unavailable");
#endif
}
void syncRoot(const fs::path& p){
#ifndef _WIN32
 int fd=open(p.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
 if(fd<0)throw std::runtime_error("pairing_invalidation_unavailable");
 auto result=fsync(fd);close(fd);if(result)throw std::runtime_error("pairing_invalidation_unavailable");
#else
 // CreateDirectory is a synchronous namespace operation; there is no secret file.
 (void)p;
#endif
}
}
bool invalidated(const std::string& id){checkId(id);try{return markerExists(root()/id);}catch(...){throw std::runtime_error("pairing_invalidation_unavailable");}}
void invalidate(const std::string& id){checkId(id);try{auto p=root();ensureRoot(p);auto marker=p/id;
 if(!markerExists(marker))fs::create_directory(marker);
 if(!fs::is_directory(fs::symlink_status(marker)))throw std::runtime_error("pairing_invalidation_unavailable");
 syncRoot(p);
 }catch(...){throw std::runtime_error("pairing_invalidation_unavailable");}}
void acceptFreshPairing(const std::string& id){checkId(id);try{auto p=root();if(!markerExists(p/id))return;
 ensureRoot(p);fs::remove(p/id);syncRoot(p);
 }catch(...){throw std::runtime_error("pairing_invalidation_unavailable");}}
std::vector<std::string> invalidatedCards(){try{auto p=root();std::vector<std::string> ids;if(!markerExists(p))return ids;
 if(!fs::is_directory(fs::symlink_status(p)))throw std::runtime_error("pairing_invalidation_unavailable");
 for(auto& entry:fs::directory_iterator(p)){auto id=entry.path().filename().string();checkId(id);ids.push_back(id);}
 std::sort(ids.begin(),ids.end());return ids;
 }catch(...){throw std::runtime_error("pairing_invalidation_unavailable");}}
}
