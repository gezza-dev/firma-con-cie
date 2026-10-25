// SPDX-License-Identifier: BSD-3-Clause
// Public DER only. No PIN, card calls, pairing-prefix reads or browser databases.
#include "local_cache.h"
#include "paired_store.h"
#include "snap_public_store.h"
#include <openssl/x509.h>
#include <iostream>
#include <iterator>
#include <cstring>

int main(int argc, char** argv) {
 try {
  if(argc!=3)return 2;
  const std::string operation(argv[1]), id(argv[2]);
  if(operation!="validate"&&operation!="check-web"&&operation!="check-snap"&&operation!="publish-web"&&operation!="publish-snap")return 2;
  cie_pairing::checkId(id);
  cie_cache::Bytes der;
  char byte;while(std::cin.get(byte)){if(der.size()>=8192)return 2;der.push_back(uint8_t(byte));}
  const auto* p=der.data();
  X509* certificate=der.empty()?nullptr:d2i_X509(nullptr,&p,long(der.size()));
  EVP_PKEY* key=certificate?X509_get_pubkey(certificate):nullptr;
  const bool valid=certificate&&p==der.data()+der.size()&&key&&EVP_PKEY_is_a(key,"RSA")&&EVP_PKEY_get_bits(key)==2048;
  EVP_PKEY_free(key);X509_free(certificate);
  if(!valid)return 2;
  if(operation=="validate")return 0;
  const bool snap=operation=="check-snap"||operation=="publish-snap";
  if(operation.rfind("check-",0)==0){
   if(snap)return cie_linux_snap::read(id)==der?0:3;
   cie_cache::Store store;
   return store.read("web",id)==der?0:3;
  }
  if(snap)return cie_linux_snap::publish(id,der.data(),uint32_t(der.size()))?0:3;
  cie_cache::Store store(true);store.write("web",id,der);return 0;
 }catch(...){return 4;}
}
