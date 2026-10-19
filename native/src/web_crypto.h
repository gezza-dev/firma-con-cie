// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "web_policy.h"
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <memory>
namespace cie_web {
inline bool verify(EVP_PKEY* key,const uint8_t* info,uint32_t length,const uint8_t* signature,uint32_t size){
 if(!key||EVP_PKEY_get_bits(key)!=2048||size!=256||!digestInfo(info,length)||!signature)return false;
 std::unique_ptr<EVP_PKEY_CTX,decltype(&EVP_PKEY_CTX_free)> ctx(EVP_PKEY_CTX_new(key,nullptr),EVP_PKEY_CTX_free);
 return ctx&&EVP_PKEY_verify_init(ctx.get())>0&&EVP_PKEY_CTX_set_rsa_padding(ctx.get(),RSA_PKCS1_PADDING)>0&&
 EVP_PKEY_verify(ctx.get(),signature,size,info,length)==1;
}
}
