// SPDX-License-Identifier: BSD-3-Clause
// Test-only PC/SC and Web engine; never links to or calls physical hardware.
#include "cie_web.h"
#include "web_policy.h"
#include "local_cache.h"
#include <winscard.h>
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>
#include <array>
#include <atomic>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
namespace {
std::array<std::atomic<unsigned>,16> metrics{};
std::atomic<bool> present{true},changed{false},busy{false},failSign{false},reset{false},locked{false};
std::string identity(){return changed?"TESTLINUX000002":"TESTLINUX000001";}
struct Fixture {
    EVP_PKEY* key=nullptr; std::vector<uint8_t> der;
    Fixture(){
        key=EVP_RSA_gen(2048);auto cert=X509_new();X509_set_version(cert,2);
        ASN1_INTEGER_set(X509_get_serialNumber(cert),1);X509_gmtime_adj(X509_getm_notBefore(cert),-60);
        X509_gmtime_adj(X509_getm_notAfter(cert),3600);X509_set_pubkey(cert,key);
        auto name=X509_get_subject_name(cert);const unsigned char label[]="Synthetic CIE Linux PKCS11";
        X509_NAME_add_entry_by_txt(name,"CN",MBSTRING_ASC,label,-1,-1,0);X509_set_issuer_name(cert,name);
        X509_sign(cert,key,EVP_sha256());int n=i2d_X509(cert,nullptr);der.resize(n);auto p=der.data();i2d_X509(cert,&p);X509_free(cert);
    }
    ~Fixture(){EVP_PKEY_free(key);}
};
Fixture& fixture(){static Fixture value;return value;}
}
struct CieWebSession {bool authenticated=false,attempted=false;std::string id;};
extern "C" {
__attribute__((visibility("default"))) unsigned CieTestMetric(unsigned index){return index<metrics.size()?metrics[index].load():0;}
__attribute__((visibility("default"))) void CieTestControl(unsigned kind,unsigned value){
    if(kind==0){present=true;changed=false;busy=false;failSign=false;reset=false;locked=false;for(auto& value:metrics)value=0;}
    if(kind==1)present=value;
    if(kind==2)changed=value;
    if(kind==3)busy=value;
    if(kind==4)failSign=value;
    if(kind==5)reset=value;
    if(kind==6)locked=value;
}
uint32_t cie_web_abi_version(){return 1;}
int32_t cie_web_open(const uint8_t*,uint32_t,CieWebTransmit,void*,const char* expected,CieWebSession** out){
    ++metrics[0];
    if(!present || (expected&&expected!=identity()))return CIE_WEB_IDENTITY;
    *out=new CieWebSession;(*out)->id=identity();return 0;
}
void cie_web_close(CieWebSession* session){++metrics[1];delete session;}
int32_t cie_web_identifier(CieWebSession* session,char* out,uint32_t* size){
    if(!out||!size||*size<=session->id.size())return CIE_WEB_BUFFER;
    std::memcpy(out,session->id.c_str(),session->id.size()+1);*size=session->id.size()+1;return 0;
}
int32_t cie_web_set_certificate(CieWebSession*,const uint8_t* der,uint32_t size){
    ++metrics[12];
    return fixture().der==std::vector<uint8_t>(der,der+size)?0:CIE_WEB_IDENTITY;
}
int32_t cie_web_certificate(CieWebSession*,uint8_t* out,uint32_t* size){
    auto capacity=*size;*size=fixture().der.size();
    if(!out)return 0;
    if(capacity<*size)return CIE_WEB_BUFFER;
    std::memcpy(out,fixture().der.data(),*size);return 0;
}
int32_t cie_web_authenticate(CieWebSession* session,char* pin,uint32_t size){
    ++metrics[2];bool ok=size==8&&!std::memcmp(pin,"12345678",8);cie_web::wipe(pin,size);
    if(session->attempted)return CIE_WEB_STATE;
    session->attempted=true;
    if(locked)return 0x6983;
    if(!ok)return 0x63c2;
    session->authenticated=true;return 0;
}
int32_t cie_web_sign(CieWebSession* session,const uint8_t* data,uint32_t length,uint8_t* out,uint32_t* size){
    if(!session->authenticated)return CIE_WEB_AUTH_REQUIRED;
    if(!present || failSign)return CIE_WEB_TRANSPORT;
    if(!cie_web::digestInfo(data,length))return CIE_WEB_ALGORITHM;
    if(!out){*size=256;return 0;}if(*size<256){*size=256;return CIE_WEB_BUFFER;}
    ++metrics[3];size_t n=*size;
    auto ctx=EVP_PKEY_CTX_new(fixture().key,nullptr);
    bool ok=ctx&&EVP_PKEY_sign_init(ctx)>0&&EVP_PKEY_CTX_set_rsa_padding(ctx,RSA_PKCS1_PADDING)>0&&EVP_PKEY_sign(ctx,out,&n,data,length)>0;
    EVP_PKEY_CTX_free(ctx);*size=n;return ok?0:CIE_WEB_CARD;
}
const SCARD_IO_REQUEST g_rgSCardT0Pci={SCARD_PROTOCOL_T0,sizeof(SCARD_IO_REQUEST)};
const SCARD_IO_REQUEST g_rgSCardT1Pci={SCARD_PROTOCOL_T1,sizeof(SCARD_IO_REQUEST)};
LONG SCardEstablishContext(DWORD,LPCVOID,LPCVOID,LPSCARDCONTEXT out){++metrics[4];*out=1;return SCARD_S_SUCCESS;}
LONG SCardReleaseContext(SCARDCONTEXT){++metrics[5];return 0;}
LONG SCardListReaders(SCARDCONTEXT,LPCSTR,LPSTR out,LPDWORD count){
    const char readers[]="Synthetic Reader\0";
    if(out){if(*count<sizeof(readers))return SCARD_E_INSUFFICIENT_BUFFER;std::memcpy(out,readers,sizeof(readers));}*count=sizeof(readers);return 0;
}
LONG SCardGetStatusChange(SCARDCONTEXT,DWORD,SCARD_READERSTATE* states,DWORD count){
    for(DWORD i=0;i<count;++i){states[i].dwEventState=present?SCARD_STATE_PRESENT:SCARD_STATE_EMPTY;states[i].cbAtr=present?2:0;states[i].rgbAtr[0]=0x3b;states[i].rgbAtr[1]=0;}
    return 0;
}
LONG SCardConnect(SCARDCONTEXT,LPCSTR,DWORD share,DWORD, LPSCARDHANDLE out,LPDWORD protocol){
    ++metrics[6];
    if(share!=SCARD_SHARE_EXCLUSIVE || busy)return SCARD_E_SHARING_VIOLATION;
    if(!present)return SCARD_E_NO_SMARTCARD;
    *out=1;*protocol=SCARD_PROTOCOL_T1;return 0;
}
LONG SCardBeginTransaction(SCARDHANDLE){++metrics[7];return 0;}
LONG SCardEndTransaction(SCARDHANDLE,DWORD disposition){++metrics[8];
    if(disposition==SCARD_RESET_CARD)++metrics[9];
    return 0;}
LONG SCardDisconnect(SCARDHANDLE,DWORD){++metrics[10];return 0;}
LONG SCardStatus(SCARDHANDLE,LPSTR,LPDWORD,LPDWORD state,LPDWORD protocol,LPBYTE atr,LPDWORD n){
    if(!present)return SCARD_W_REMOVED_CARD;
    if(reset)return SCARD_W_RESET_CARD;

    *state=SCARD_SPECIFIC;*protocol=SCARD_PROTOCOL_T1;atr[0]=0x3b;atr[1]=0;*n=2;return 0;
}
LONG SCardTransmit(SCARDHANDLE,const SCARD_IO_REQUEST*,LPCBYTE,DWORD,SCARD_IO_REQUEST*,LPBYTE,LPDWORD){++metrics[11];return SCARD_E_NOT_TRANSACTED;}
}
extern "C" __attribute__((visibility("default"))) unsigned CieTestCertificate(unsigned char* out,unsigned capacity){
    auto& der=fixture().der;if(out && capacity>=der.size())std::memcpy(out,der.data(),der.size());return der.size();
}

extern "C" __attribute__((visibility("default"))) void CieTestSeedPublic(){
    cie_cache::Store store(true);auto& der=fixture().der;
    cie_cache::Bytes cert(der.begin(),der.end());store.write("web",identity(),cert);
    // Deliberately unusable PIN-pairing bytes: the Web provider must not read
    // this namespace, reconstruct a prefix or use it to authenticate.
    cie_cache::Bytes invalidPrefix{0xff,0,0};store.write("card",identity(),invalidPrefix);
}
