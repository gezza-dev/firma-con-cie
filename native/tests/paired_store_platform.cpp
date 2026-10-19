// SPDX-License-Identifier: BSD-3-Clause
// Separate OS credential namespace. Contains synthetic digits only.
#include "paired_store.h"
#include <iostream>
#include <chrono>
#include <cstring>
int main(){
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
  publicData.assign(2560,7);cie_pairing::writePublic(id,publicData);if(cie_pairing::readPublic(id)!=publicData)return 18;
  bool oversizedRejected=false;try{cie_pairing::writePublic(id,std::vector<uint8_t>(2561,8));}catch(const std::exception& e){oversizedRejected=std::string(e.what())=="pairing_public_too_large";}
  if(!oversizedRejected)return 19;if(cie_pairing::readPublic(id)!=publicData)return 20;
#endif
  cie_pairing::invalidate(id);
  if(cie_pairing::read(id,value))return 15;
  auto blocked=cie_pairing::list();if(std::find(blocked.begin(),blocked.end(),id)!=blocked.end())return 16;
  cie_pairing::acceptFreshPairing(id);if(!cie_pairing::read(id,value))return 17;
  cie_pairing::erasePublic(id);cie_pairing::erasePublic(id);if(cie_pairing::listPublic()!=beforePublic)return 12;
  cie_pairing::erase(id);cie_pairing::erase(id);if(cie_pairing::read(id,value)||cie_pairing::list()!=before)return 5;
  std::cout<<"{\"passed\":true,\"checks\":"<<
#ifdef _WIN32
  20
#else
  17
#endif
  <<",\"syntheticCredentialNamespace\":true,\"testRecordsRemoved\":true}\n";return 0;
 }catch(const cie_pairing::StoreError& e){std::cerr<<"Protected credential test failed: OS status="<<e.nativeCode<<"\n";return 6;}catch(...){std::cerr<<"Protected credential test failed; no fallback\n";return 6;}
}
