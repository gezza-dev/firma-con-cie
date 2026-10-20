// SPDX-License-Identifier: BSD-3-Clause
// Separate File cache namespace. Contains synthetic digits only.
#include "paired_store.h"
#include <iostream>
#include <chrono>
#include <cstring>
#ifndef CIE_PAIRING_TEST_SERVICE
#error "File cache tests require the isolated test service"
#endif
#include <filesystem>
#include <cstdlib>
// Explicit subprocess persistence tests use only the test cache override.
int persistent(const std::string& mode,const std::string& id){
 if(id.rfind("TESTMIG",0)||!cie_pairing::validId(id))return 21;
 if(mode=="seed"){
  cie_pairing::prepare();cie_pairing::write(id,"1234");cie_pairing::writePublic(id,{1,2,3});
 }else if(mode=="remove"||mode=="present"){
  if(mode=="remove")cie_pairing::eraseRecord(id);
  auto publicIds=cie_pairing::listPublic(),ids=cie_pairing::list();
  bool hasPublic=std::find(publicIds.begin(),publicIds.end(),id)!=publicIds.end();
  bool hasPairing=std::find(ids.begin(),ids.end(),id)!=ids.end();
  if(mode=="remove"?(hasPublic||hasPairing):(!hasPublic||!hasPairing))return 22;
 }else return 23;
 return 0;
}
int main(int argc,char** argv){
 if(argc==3){try{return persistent(argv[1],argv[2]);}catch(const cie_pairing::StoreError& e){std::cerr<<"OS status="<<e.nativeCode<<"\n";return 24;}catch(...){return 25;}}
 auto isolated=std::filesystem::temp_directory_path()/("cie-file-cache-tests-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
 if(!std::filesystem::create_directory(isolated))return 26;
 struct DirectoryCleanup{std::filesystem::path p;~DirectoryCleanup(){std::error_code ec;std::filesystem::remove_all(p,ec);}} directoryCleanup{isolated};
#ifdef _WIN32
 if(_wputenv_s(L"CIE_PAIRING_TEST_CACHE",isolated.c_str()))return 27;
#else
 if(setenv("CIE_PAIRING_TEST_CACHE",isolated.c_str(),1))return 27;
#endif
 if(!cie_pairing::supported())return 77;
 const auto id="TEST"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
 struct Cleanup{std::string id;~Cleanup(){try{cie_pairing::erasePublic(id);cie_pairing::erase(id);cie_pairing::acceptFreshPairing(id);}catch(...){}}} cleanup{id};
 try {
  auto before=cie_pairing::list();cie_pairing::Secret value;
  if(cie_pairing::read(id,value))return 1;
  cie_pairing::write(id,"1234");if(!cie_pairing::read(id,value)||std::strcmp(value.bytes.data(),"1234"))return 2;
  cie_pairing::write(id,"5678");if(!cie_pairing::read(id,value)||std::strcmp(value.bytes.data(),"5678"))return 3;
  auto all=cie_pairing::list();if(std::find(all.begin(),all.end(),id)==all.end())return 4;
  auto beforePublic=cie_pairing::listPublic();
  if(!cie_pairing::readPublic(id).empty())return 7;
  std::vector<uint8_t> publicData{1,2,3};cie_pairing::writePublic(id,publicData);
  if(cie_pairing::readPublic(id)!=publicData)return 8;
  if(cie_pairing::list()!=all)return 9; // public record never appears as a PIN prefix
  auto publicIds=cie_pairing::listPublic();if(std::find(publicIds.begin(),publicIds.end(),id)==publicIds.end())return 10;
  publicData={4,5,6};cie_pairing::writePublic(id,publicData);if(cie_pairing::readPublic(id)!=publicData)return 11;
#ifdef _WIN32
  publicData.assign(9000,7);cie_pairing::writePublic(id,publicData);if(cie_pairing::readPublic(id)!=publicData)return 18;
  bool oversizedRejected=false;try{cie_pairing::writePublic(id,std::vector<uint8_t>(9001,8));}catch(const std::exception& e){oversizedRejected=std::string(e.what())=="pairing_public_invalid";}
  if(!oversizedRejected)return 19;if(cie_pairing::readPublic(id)!=publicData)return 20;
#endif
  cie_pairing::invalidate(id);
  if(cie_pairing::read(id,value))return 15;
  auto blocked=cie_pairing::list();if(std::find(blocked.begin(),blocked.end(),id)!=blocked.end())return 16;
  cie_pairing::acceptFreshPairing(id);if(!cie_pairing::read(id,value))return 17;
  cie_pairing::eraseForRemoval(id,true);cie_pairing::eraseForRemoval(id,true);if(cie_pairing::listPublic()!=beforePublic)return 12;
  cie_pairing::eraseForRemoval(id,false);cie_pairing::eraseForRemoval(id,false);if(cie_pairing::read(id,value)||cie_pairing::list()!=before)return 5;
  std::cout<<"{\"passed\":true,\"checks\":"<<
#ifdef _WIN32
  20
#else
  17
#endif
  <<",\"syntheticFileCacheNamespace\":true,\"testRecordsRemoved\":true}\n";return 0;
 }catch(const cie_pairing::StoreError& e){std::cerr<<"Protected credential test failed: OS status="<<e.nativeCode<<"\n";return 6;}catch(...){std::cerr<<"Protected credential test failed; no fallback\n";return 6;}
}
