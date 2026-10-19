// SPDX-License-Identifier: BSD-3-Clause
#include "cie_web.h"
#include "web_policy.h"
#include "web_crypto.h"
#include "paired_store.h"
#include "cie-pkcs11/CSP/IAS.h"
#include "cie-pkcs11/CSP/ATR.h"
#include "card_material.h"
#include <openssl/x509.h>
#include <openssl/evp.h>
#include <memory>
#include <mutex>
#undef min

struct CieWebSession {
 CieWebTransmit transmit;void* context;cie_web::State state;
 std::mutex mutex;std::unique_ptr<IAS> ias;std::string id;
 std::vector<uint8_t> certificate;uint32_t signatureSize=0;
 std::unique_ptr<EVP_PKEY,decltype(&EVP_PKEY_free)> publicKey{nullptr,EVP_PKEY_free};
 cie_pairing::PairMaterial material;bool prepared=false;
 explicit CieWebSession(CieWebTransmit t,void* c):transmit(t),context(c){}
 void secure(){auto& i=*ias;ByteDynArray data;i.attemptsRemaining=-1;
  i.InitEncKey();i.ReadDappPubKey(data);i.InitDHParam();i.InitExtAuthKeyParam();i.DHKeyExchange();i.DAPP();}
};
namespace {
// IAS pseudo-commands must never escape to the caller's system-owned session.
HRESULT transmit(void* context,uint8_t* request,DWORD length,uint8_t* response,DWORD* size){
 auto* s=static_cast<CieWebSession*>(context);
 if(!s||s->state.failed||!request||length<4||length>4096||!response||!size){if(s)s->state.fail();return SCARD_E_INVALID_PARAMETER;}
 uint32_t capacity=static_cast<uint32_t>(*size),n=capacity;
 auto status=s->transmit(s->context,request,static_cast<uint32_t>(length),response,&n);
 if(status||n<2||n>capacity){s->state.fail();return SCARD_F_COMM_ERROR;}
 *size=n;return SCARD_S_SUCCESS;
}
int32_t copy(const void* input,uint32_t length,void* output,uint32_t* size){
 if(!size)return CIE_WEB_ARGUMENT;auto capacity=*size;*size=length;
 if(!output)return CIE_WEB_OK;if(capacity<length)return CIE_WEB_BUFFER;
 std::memcpy(output,input,length);return CIE_WEB_OK;
}
void parseCertificate(CieWebSession& s,const uint8_t* der,uint32_t n){
 if(!der||!n||n>8192)throw std::runtime_error("certificate");
 const unsigned char* pos=der;const auto* end=pos+n;
 std::unique_ptr<X509,decltype(&X509_free)> cert(d2i_X509(nullptr,&pos,n),X509_free);
 if(!cert||pos!=end)throw std::runtime_error("certificate");
 std::unique_ptr<EVP_PKEY,decltype(&EVP_PKEY_free)> key(X509_get_pubkey(cert.get()),EVP_PKEY_free);
 if(!key||EVP_PKEY_base_id(key.get())!=EVP_PKEY_RSA||EVP_PKEY_get_bits(key.get())!=2048)throw std::runtime_error("key");
 s.signatureSize=EVP_PKEY_get_size(key.get());s.certificate.assign(der,der+n);
 s.publicKey=std::move(key);
}
void certificate(CieWebSession& s){
 if(!s.certificate.empty())return;
 int stage=0;if(!s.prepared){s.material.prepare(s,stage);s.prepared=true;}
 s.material.verifySod(s,stage);ByteDynArray encoded;s.ias->ReadCertCIE(encoded);
 auto n=GetASN1DataLenght(encoded);if(n>encoded.size())throw std::runtime_error("certificate");
 parseCertificate(s,encoded.data(),n);
}
}
extern "C" {
uint32_t cie_web_abi_version(){return 1;}
int32_t cie_web_open(const uint8_t* atr,uint32_t size,CieWebTransmit callback,void* context,const char* expected,CieWebSession** result){
 if(result)*result=nullptr;
 if(!result||!atr||!size||size>64||!callback||(expected&&!cie_pairing::validId(expected)))return CIE_WEB_ARGUMENT;
 try{
  if(get_type(std::vector<uint8_t>(atr,atr+size))==CIE_Unknown)return CIE_WEB_CARD;
  auto s=std::make_unique<CieWebSession>(callback,context);ByteArray bytes(const_cast<uint8_t*>(atr),size);
  s->ias=std::make_unique<IAS>(transmit,bytes);s->ias->SetCardContext(s.get());
  // No Reset: CTK/Base CSP owns transaction, power and card handle.
  s->ias->SelectAID_IAS();s->ias->ReadPAN();s->ias->SelectAID_CIE();ByteDynArray id;s->ias->ReadIdServizi(id);
  s->id.assign(reinterpret_cast<const char*>(id.data()),id.size());while(!s->id.empty()&&s->id.back()==0)s->id.pop_back();
  if(!cie_pairing::validId(s->id))return CIE_WEB_CARD;
  if(expected&&s->id!=expected)return CIE_WEB_IDENTITY;
  *result=s.release();return CIE_WEB_OK;
 }catch(...){return CIE_WEB_CARD;}
}
void cie_web_close(CieWebSession* s){delete s;}
int32_t cie_web_identifier(CieWebSession* s,char* out,uint32_t* size){
 if(!s)return CIE_WEB_ARGUMENT;std::lock_guard<std::mutex> lock(s->mutex);
 return copy(s->id.c_str(),static_cast<uint32_t>(s->id.size()+1),out,size);
}
int32_t cie_web_set_certificate(CieWebSession* s,const uint8_t* der,uint32_t size){
 if(!s||!der||!size||size>8192)return CIE_WEB_ARGUMENT;
 std::lock_guard<std::mutex> lock(s->mutex);if(s->state.failed||s->state.attempted||!s->certificate.empty())return CIE_WEB_STATE;
 try{
  ByteDynArray sod;s->ias->ReadSOD(sod);auto groups=cie_pairing::sodDigests(sod);auto found=groups.find(0xa3);
  if(found==groups.end())throw std::runtime_error("SOD certificate");
  ByteArray encoded(const_cast<uint8_t*>(der),size);auto algorithm=s->ias->GetSODDigestAlg(sod);
  if(algorithm==1){CSHA256 hash;if(hash.Digest(encoded)!=found->second)throw std::runtime_error("SOD certificate");s->ias->VerificaSOD(sod,groups);}
  else if(algorithm==2){CSHA512 hash;if(hash.Digest(encoded)!=found->second)throw std::runtime_error("SOD certificate");s->ias->VerificaSODPSS(sod,groups);}
  else throw std::runtime_error("SOD algorithm");
  parseCertificate(*s,der,size);return CIE_WEB_OK;
 }catch(...){s->state.fail();return CIE_WEB_IDENTITY;}
}
int32_t cie_web_certificate(CieWebSession* s,uint8_t* out,uint32_t* size){
 if(!s||!size)return CIE_WEB_ARGUMENT;std::lock_guard<std::mutex> lock(s->mutex);
 if(s->state.failed)return CIE_WEB_STATE;
 try{certificate(*s);return copy(s->certificate.data(),static_cast<uint32_t>(s->certificate.size()),out,size);}
 catch(...){s->state.fail();return CIE_WEB_CARD;}
}
int32_t cie_web_authenticate(CieWebSession* s,char* pin,uint32_t size){
 struct Wipe{char* p;uint32_t n;~Wipe(){cie_web::wipe(p,n);}} wipe{pin,size};
 if(!s||!pin||size!=8||!std::all_of(pin,pin+size,[](char c){return c>='0'&&c<='9';}))return CIE_WEB_ARGUMENT;
 std::lock_guard<std::mutex> lock(s->mutex);
 if(!s->state.beginAuthentication())return CIE_WEB_STATE;
 try{
  int stage=0;if(!s->prepared){s->material.prepare(*s,stage);s->prepared=true;}
  ByteArray secret(reinterpret_cast<uint8_t*>(pin),8);auto sw=s->ias->VerifyPIN(secret);
  if(sw!=0x9000){s->state.fail();return sw;}
  // Verify all six DG after authentication even when discovery used a cached
  // certificate. Compare the live certificate before enabling private signing.
  s->material.verifySod(*s,stage);ByteDynArray live;s->ias->ReadCertCIE(live);auto n=GetASN1DataLenght(live);
  if(n>live.size())throw std::runtime_error("certificate");
  if(!s->certificate.empty()&&(s->certificate.size()!=n||std::memcmp(s->certificate.data(),live.data(),n)))throw std::runtime_error("certificate changed");
  if(s->certificate.empty())parseCertificate(*s,live.data(),n);
  s->state.authenticated=true;return CIE_WEB_OK;
 }catch(...){s->state.fail();return CIE_WEB_CARD;}
}
int32_t cie_web_sign(CieWebSession* s,const uint8_t* data,uint32_t length,uint8_t* out,uint32_t* size){
 if(!s||!size)return CIE_WEB_ARGUMENT;
 if(!cie_web::digestInfo(data,length))return CIE_WEB_ALGORITHM;
 std::lock_guard<std::mutex> lock(s->mutex);
 if(s->state.failed)return CIE_WEB_STATE;if(!s->state.authenticated)return CIE_WEB_AUTH_REQUIRED;
 if(!out||*size<s->signatureSize){auto small=out!=nullptr;*size=s->signatureSize;return small?CIE_WEB_BUFFER:CIE_WEB_OK;}
 try{ByteArray input(const_cast<uint8_t*>(data),length);ByteDynArray result;s->ias->Sign(input,result);
  if(result.size()!=s->signatureSize||!cie_web::verify(s->publicKey.get(),data,length,result.data(),result.size()))throw std::runtime_error("signature");
  return copy(result.data(),result.size(),out,size);
 }catch(...){s->state.fail();return CIE_WEB_CARD;}
}
}
