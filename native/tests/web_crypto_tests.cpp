// SPDX-License-Identifier: BSD-3-Clause
#include "web_crypto.h"
#include <stdexcept>
#include <iostream>
#include <vector>
static int checks=0;
static void check(bool value){++checks;if(!value)throw std::runtime_error("web crypto regression");}
int main(){
 std::unique_ptr<EVP_PKEY_CTX,decltype(&EVP_PKEY_CTX_free)> generator(EVP_PKEY_CTX_new_id(EVP_PKEY_RSA,nullptr),EVP_PKEY_CTX_free);
 EVP_PKEY* raw=nullptr;check(generator&&EVP_PKEY_keygen_init(generator.get())>0&&EVP_PKEY_CTX_set_rsa_keygen_bits(generator.get(),2048)>0&&EVP_PKEY_keygen(generator.get(),&raw)>0);
 std::unique_ptr<EVP_PKEY,decltype(&EVP_PKEY_free)> key(raw,EVP_PKEY_free);
 for(unsigned algorithm=1;algorithm<=3;++algorithm){unsigned n=algorithm==1?32:algorithm==2?48:64;
  uint8_t prefix[]={0x30,static_cast<uint8_t>(17+n),0x30,0x0d,0x06,0x09,0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,static_cast<uint8_t>(algorithm),0x05,0,0x04,static_cast<uint8_t>(n)};
  std::vector<uint8_t> encoded(prefix,prefix+19);encoded.resize(19+n,0x12);
  std::unique_ptr<EVP_PKEY_CTX,decltype(&EVP_PKEY_CTX_free)> ctx(EVP_PKEY_CTX_new(key.get(),nullptr),EVP_PKEY_CTX_free);
  check(ctx&&EVP_PKEY_sign_init(ctx.get())>0&&EVP_PKEY_CTX_set_rsa_padding(ctx.get(),RSA_PKCS1_PADDING)>0);
  uint8_t signature[256];size_t size=sizeof(signature);check(EVP_PKEY_sign(ctx.get(),signature,&size,encoded.data(),encoded.size())>0);
  check(cie_web::verify(key.get(),encoded.data(),encoded.size(),signature,size));
  signature[128]^=1;check(!cie_web::verify(key.get(),encoded.data(),encoded.size(),signature,size));signature[128]^=1;
  encoded.back()^=1;check(!cie_web::verify(key.get(),encoded.data(),encoded.size(),signature,size));
  check(!cie_web::verify(key.get(),encoded.data(),encoded.size(),signature,255));
 }
 std::cout<<checks<<" web RSA verification checks passed\n";
}
