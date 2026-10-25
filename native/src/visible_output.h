// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <filesystem>
#include <stdexcept>
#include <chrono>
#include <cerrno>
#include <fstream>
#include <cstring>
#ifdef __linux__
#include <cstdlib>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/fs.h>
#endif
#ifdef __APPLE__
#include <sys/stat.h>
#include <sys/xattr.h>
#include <stdio.h>
#elif defined(_WIN32)
#include <windows.h>
#endif
namespace cie {
inline void makeOutputVisible(const std::filesystem::path& path) {
#ifdef __APPLE__
 struct stat st{};
 if(stat(path.c_str(),&st)||chflags(path.c_str(),st.st_flags&~UF_HIDDEN))throw std::runtime_error("output_visibility_failed");
 // Finder's legacy invisibility bit is independent of the BSD hidden flag.
 unsigned char finder[32]{};auto size=getxattr(path.c_str(),"com.apple.FinderInfo",finder,sizeof(finder),0,0);
 if(size>=10&&(finder[8]&0x40)){finder[8]&=~0x40;if(setxattr(path.c_str(),"com.apple.FinderInfo",finder,size,0,0))throw std::runtime_error("output_visibility_failed");}
 if(stat(path.c_str(),&st)||(st.st_flags&UF_HIDDEN))throw std::runtime_error("output_visibility_failed");
#elif defined(_WIN32)
 auto flags=GetFileAttributesW(path.c_str());if(flags==INVALID_FILE_ATTRIBUTES)throw std::runtime_error("output_visibility_failed");
 if(flags&FILE_ATTRIBUTE_HIDDEN){flags&=~FILE_ATTRIBUTE_HIDDEN;if(!SetFileAttributesW(path.c_str(),flags?flags:FILE_ATTRIBUTE_NORMAL))throw std::runtime_error("output_visibility_failed");}
#else
 (void)path;
#endif
}
// Neither the directory nor the payload has a dot-prefixed name. File Provider
// must never observe a hidden pathname for the inode eventually given to users.
// Staging is private, exclusive and on the destination filesystem. A Linux
// single-file document portal permits temporary sibling files, but no mkdir
// or hard links; publish those files with an atomic no-replace rename.
class OutputStaging {
 std::filesystem::path directory_;
 std::filesystem::path previous_;
 std::filesystem::file_time_type previousTime_{};
 bool siblingFile_=false;
#ifdef __linux__
 static std::filesystem::path temporarySibling(const std::filesystem::path& parent,const std::string& extension){
  const auto suffix="."+extension;
  auto name=(parent/("CIE-ID-elaborazione-XXXXXX"+suffix)).string();
  std::vector<char> buffer(name.begin(),name.end());buffer.push_back(0);
  int fd=mkostemps(buffer.data(),int(suffix.size()),O_CLOEXEC);
  if(fd<0)throw std::filesystem::filesystem_error("output_staging_failed",parent,{errno,std::generic_category()});
  if(close(fd)){const int saved=errno;unlink(buffer.data());throw std::system_error(saved,std::generic_category(),"output_staging_failed");}
  return std::filesystem::path(buffer.data());
 }
#endif
public:
 std::filesystem::path file;
 OutputStaging(const std::filesystem::path& parent,const std::string& extension){
  directory_=parent/std::filesystem::u8path("CIE-ID-elaborazione-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
  std::error_code ec;
  if(!std::filesystem::create_directory(directory_,ec)){
#ifdef __linux__
   if(ec==std::errc::operation_not_permitted){
    file=temporarySibling(parent,extension);directory_.clear();siblingFile_=true;return;
   }
#endif
   if(ec)throw std::filesystem::filesystem_error("cannot create directory",directory_,ec);
   throw std::runtime_error("output_staging_failed");
  }
  try{std::filesystem::permissions(directory_,std::filesystem::perms::owner_all,std::filesystem::perm_options::replace);file=directory_/std::filesystem::u8path("documento."+extension);}
  catch(...){std::error_code ec;std::filesystem::remove(directory_,ec);throw;}
 }
 OutputStaging(const OutputStaging&)=delete;
 ~OutputStaging(){std::error_code ec;if(siblingFile_){std::filesystem::remove(file,ec);if(!previous_.empty())std::filesystem::remove(previous_,ec);}else std::filesystem::remove_all(directory_,ec);}
 void prepareReplacement(const std::filesystem::path& destination){
  if(!std::filesystem::is_regular_file(std::filesystem::symlink_status(destination)))throw std::runtime_error("output_not_regular");
  previousTime_=std::filesystem::last_write_time(destination);
#ifdef __linux__
  if(siblingFile_){
   previous_=temporarySibling(file.parent_path(),"backup");
   std::filesystem::copy_file(destination,previous_,std::filesystem::copy_options::overwrite_existing);
   std::filesystem::permissions(previous_,std::filesystem::perms::owner_read|std::filesystem::perms::owner_write,std::filesystem::perm_options::replace);
   return;
  }
#endif
  previous_=directory_/"precedente";std::filesystem::copy_file(destination,previous_);
 }
 bool replacementUnchanged(const std::filesystem::path& destination) const {
  if(previous_.empty())return false;
  if(!std::filesystem::is_regular_file(std::filesystem::symlink_status(destination)) ||
     std::filesystem::last_write_time(destination)!=previousTime_ ||
     std::filesystem::file_size(destination)!=std::filesystem::file_size(previous_))return false;
  std::ifstream a(destination,std::ios::binary),b(previous_,std::ios::binary);
  char x[65536],y[65536];
  while(a&&b){a.read(x,sizeof(x));b.read(y,sizeof(y));if(a.gcount()!=b.gcount() || std::memcmp(x,y,size_t(a.gcount())))return false;}
  return a.eof()&&b.eof();
 }
 std::error_code publish(const std::filesystem::path& destination,bool replace=false){
  std::error_code ec;
#ifdef __linux__
  if(siblingFile_){
   if(replace&&!replacementUnchanged(destination))return std::make_error_code(std::errc::state_not_recoverable);
   if(syscall(SYS_renameat2,AT_FDCWD,file.c_str(),AT_FDCWD,destination.c_str(),replace?0:RENAME_NOREPLACE))return {errno,std::generic_category()};
   return {};
  }
#endif
  if(replace){
   if(!replacementUnchanged(destination))return std::make_error_code(std::errc::state_not_recoverable);
   // Clear inherited visibility before replacing an existing good file.
   makeOutputVisible(file);
#ifdef _WIN32
   if(!MoveFileExW(file.c_str(),destination.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))return {int(GetLastError()),std::system_category()};
#else
   std::filesystem::rename(file,destination,ec);if(ec)return ec;
#endif
   makeOutputVisible(destination);return {};
  }
#ifdef __APPLE__
  // Atomic no-replace move: no second (hidden) alias of the final inode.
  if(renamex_np(file.c_str(),destination.c_str(),RENAME_EXCL))return {errno,std::generic_category()};
#elif defined(_WIN32)
  if(!MoveFileExW(file.c_str(),destination.c_str(),MOVEFILE_WRITE_THROUGH))return {int(GetLastError()),std::system_category()};
#else
  std::filesystem::create_hard_link(file,destination,ec);if(ec)return ec;
  std::filesystem::remove(file,ec);
#endif
  // Operate on the visible final pathname, after removing the staging name.
  makeOutputVisible(destination);return {};
 }
};
}
