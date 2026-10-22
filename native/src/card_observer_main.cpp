// SPDX-License-Identifier: BSD-3-Clause
// Private, read-only PC/SC worker. No PIN, signing, enrollment or cache API.
#include "cie_bridge.h"
#include <condition_variable>
#include <cstdlib>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#endif

int main(int argc, char** argv) {
 if(argc!=3)return 64;
 std::string middleware=argv[1],adapter=argv[2];
#ifdef _WIN32
 // CRT narrow argv uses the system code page. The bridge ABI requires UTF-8,
 // including installations under a user directory containing non-ASCII text.
 int count=0;auto wide=CommandLineToArgvW(GetCommandLineW(),&count);
 if(!wide||count!=3){if(wide)LocalFree(wide);return 64;}
 auto utf8=[](const wchar_t* text){
  int size=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,text,-1,nullptr,0,nullptr,nullptr);
  if(size<=0)return std::string();
  std::string value(size,'\0');
  WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,text,-1,value.data(),size,nullptr,nullptr);
  value.pop_back();return value;
 };
 middleware=utf8(wide[1]);adapter=utf8(wide[2]);LocalFree(wide);
 if(middleware.empty())return 64;
#endif
 std::mutex mutex;
 std::condition_variable changed;
 std::string pending;
 // EOF is the parent-lifetime signal. It must still be serviced when PC/SC
 // blocks forever on the operation thread. This worker owns no private work.
 std::thread([&]{
  std::string line;
  while(std::getline(std::cin,line)){
   if(line!="observe"&&line!="detect")std::_Exit(64);
   {std::lock_guard<std::mutex> lock(mutex);
    if(!pending.empty())std::_Exit(64);
    pending=line;}
   changed.notify_one();
  }
  std::_Exit(0);
 }).detach();
 char* loaded=cie_bridge_load(middleware.c_str(),adapter.c_str());
 if(!loaded)std::_Exit(70);
 // Let the bridge report a missing/incompatible runtime through its own JSON.
 std::string loadResult(loaded);cie_bridge_free(loaded);
 if(loadResult.find("\"ok\":true")==std::string::npos){
  std::cout<<"CIE_OBSERVER_JSON="<<loadResult<<std::endl;std::_Exit(70);
 }
 for(;;){
  std::string command;
  {std::unique_lock<std::mutex> lock(mutex);
   changed.wait(lock,[&]{return !pending.empty();});command.swap(pending);}
  char* value=command=="observe"?cie_bridge_observe():cie_bridge_detect();
  if(!value)std::_Exit(70);
  std::cout<<"CIE_OBSERVER_JSON="<<value<<std::endl;
  cie_bridge_free(value);
 }
}
