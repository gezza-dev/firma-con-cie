// SPDX-License-Identifier: BSD-3-Clause
#include "local_cache.h"
#include <algorithm>
#include <cstring>
#include <stdexcept>
#ifdef __APPLE__
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonHMAC.h>
#include <Security/SecRandom.h>
#elif defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <bcrypt.h>
#else
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#endif
namespace cie_cache {
namespace {
constexpr uint8_t magic[]={'C','I','E','C','A','C','H',3};
void check(bool ok){if(!ok)throw std::runtime_error("pairing_cache_invalid");}
#ifdef _WIN32
struct Algorithm {BCRYPT_ALG_HANDLE p=nullptr;~Algorithm(){if(p)BCryptCloseAlgorithmProvider(p,0);}};
#endif
Bytes crypt(bool encrypting,const Bytes& key,const uint8_t* iv,const uint8_t* input,size_t size){
 Bytes out(size+16);size_t written=0;
#ifdef __APPLE__
 check(CCCrypt(encrypting?kCCEncrypt:kCCDecrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,
  key.data(),32,iv,input,size,out.data(),out.size(),&written)==kCCSuccess);
#elif defined(_WIN32)
 Algorithm algorithm;check(!BCryptOpenAlgorithmProvider(&algorithm.p,BCRYPT_AES_ALGORITHM,nullptr,0));
 check(!BCryptSetProperty(algorithm.p,BCRYPT_CHAINING_MODE,(PUCHAR)BCRYPT_CHAIN_MODE_CBC,sizeof(BCRYPT_CHAIN_MODE_CBC),0));
 DWORD objectSize=0,n=0;check(!BCryptGetProperty(algorithm.p,BCRYPT_OBJECT_LENGTH,(PUCHAR)&objectSize,sizeof(objectSize),&n,0));
 Bytes object(objectSize);BCRYPT_KEY_HANDLE handle=nullptr;
 check(!BCryptGenerateSymmetricKey(algorithm.p,&handle,object.data(),objectSize,const_cast<PUCHAR>(key.data()),32,0));
 struct Free {BCRYPT_KEY_HANDLE p;~Free(){BCryptDestroyKey(p);}} free{handle};
 uint8_t ivCopy[16];std::memcpy(ivCopy,iv,16);ULONG count=0;
 auto status=encrypting?BCryptEncrypt(handle,const_cast<PUCHAR>(input),(ULONG)size,nullptr,ivCopy,16,out.data(),(ULONG)out.size(),&count,BCRYPT_BLOCK_PADDING):
  BCryptDecrypt(handle,const_cast<PUCHAR>(input),(ULONG)size,nullptr,ivCopy,16,out.data(),(ULONG)out.size(),&count,BCRYPT_BLOCK_PADDING);
 check(!status);written=count;
#else
 auto context=EVP_CIPHER_CTX_new();check(context!=nullptr);
 struct Free {EVP_CIPHER_CTX* p;~Free(){EVP_CIPHER_CTX_free(p);}} free{context};
 int count=0,tail=0;check(EVP_CipherInit_ex(context,EVP_aes_256_cbc(),nullptr,key.data(),iv,encrypting?1:0)==1);
 check(EVP_CipherUpdate(context,out.data(),&count,input,(int)size)==1);
 check(EVP_CipherFinal_ex(context,out.data()+count,&tail)==1);written=size_t(count+tail);
#endif
 // Wipe the unused padding area before shrinking the plaintext buffer.
 volatile uint8_t* p=out.data();for(size_t i=written;i<out.size();++i)p[i]=0;
 out.resize(written);return out;
}
Bytes mac(const uint8_t* secret,size_t secretSize,const uint8_t* input,size_t inputSize){
 Bytes out(32);
#ifdef __APPLE__
 CCHmac(kCCHmacAlgSHA256,secret,secretSize,input,inputSize,out.data());
#elif defined(_WIN32)
 Algorithm algorithm;check(!BCryptOpenAlgorithmProvider(&algorithm.p,BCRYPT_SHA256_ALGORITHM,nullptr,BCRYPT_ALG_HANDLE_HMAC_FLAG));
 DWORD objectSize=0,n=0;check(!BCryptGetProperty(algorithm.p,BCRYPT_OBJECT_LENGTH,(PUCHAR)&objectSize,sizeof(objectSize),&n,0));
 Bytes object(objectSize);BCRYPT_HASH_HANDLE handle=nullptr;
 check(!BCryptCreateHash(algorithm.p,&handle,object.data(),objectSize,const_cast<PUCHAR>(secret),(ULONG)secretSize,0));
 struct Free {BCRYPT_HASH_HANDLE p;~Free(){BCryptDestroyHash(p);}} free{handle};
 check(!BCryptHashData(handle,const_cast<PUCHAR>(input),(ULONG)inputSize,0));check(!BCryptFinishHash(handle,out.data(),32,0));
#else
 unsigned n=0;check(HMAC(EVP_sha256(),secret,secretSize,input,inputSize,out.data(),&n)!=nullptr&&n==32);
#endif
 return out;
}
Bytes derived(const Bytes& master){
 // Independent, labelled HMAC-SHA256 subkeys. Every master-key byte affects
 // both subkeys, so damage to the encryption half cannot leave a valid MAC.
 Bytes keys;keys.reserve(64);for(const char* label:{"CIE-ID cache v3 encryption","CIE-ID cache v3 authentication"}){
  auto part=mac(master.data(),master.size(),(const uint8_t*)label,std::strlen(label));keys.insert(keys.end(),part.begin(),part.end());
 }return keys;
}
Bytes tag(const Bytes& key,const std::string& binding,const uint8_t* bytes,size_t size){
 Bytes input(binding.begin(),binding.end());input.push_back(0);input.insert(input.end(),bytes,bytes+size);
 return mac(key.data()+32,32,input.data(),input.size());
}
}
void random(uint8_t* out,size_t size){
#ifdef __APPLE__
 check(SecRandomCopyBytes(kSecRandomDefault,size,out)==errSecSuccess);
#elif defined(_WIN32)
 check(size<=16384&&!BCryptGenRandom(nullptr,out,(ULONG)size,BCRYPT_USE_SYSTEM_PREFERRED_RNG));
#else
 check(size<=16384&&RAND_bytes(out,(int)size)==1);
#endif
}
Bytes encrypt(const Bytes& key,const std::string& binding,const Bytes& plaintext){
 check(key.size()==64&&!plaintext.empty()&&plaintext.size()<=10000);Bytes out(std::begin(magic),std::end(magic));out.resize(24);random(out.data()+8,16);
 auto keys=derived(key);auto cipher=crypt(true,keys,out.data()+8,plaintext.data(),plaintext.size());out.insert(out.end(),cipher.begin(),cipher.end());
 auto mac=tag(keys,binding,out.data(),out.size());out.insert(out.end(),mac.begin(),mac.end());return out;
}
Bytes decrypt(const Bytes& key,const std::string& binding,const Bytes& encoded){
 check(key.size()==64&&encoded.size()>=72&&encoded.size()<=10100&&(encoded.size()-56)%16==0&&
  std::equal(std::begin(magic),std::end(magic),encoded.begin()));
 auto keys=derived(key);auto size=encoded.size()-32;auto mac=tag(keys,binding,encoded.data(),size);unsigned difference=0;
 for(size_t i=0;i<32;++i)difference|=mac[i]^encoded[size+i];check(difference==0);
 // Encrypt-then-MAC: never parse padding/plaintext before authentication.
 return crypt(false,keys,encoded.data()+8,encoded.data()+24,size-24);
}
}
