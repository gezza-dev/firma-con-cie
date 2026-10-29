// SPDX-License-Identifier: BSD-3-Clause
// Every card/PCSC entry point in the loaded module is a test double.
#include "../pkcs11_api.h"
#include "web_policy.h"
#include <openssl/x509.h>
#include <openssl/rsa.h>
#ifdef _WIN32
#include <windows.h>
#include <cstdlib>
static void* dlopen(const char* name,int){return LoadLibraryA(name);}
static auto dlsym(void* module,const char* name){return GetProcAddress(static_cast<HMODULE>(module),name);}
static void dlclose(void* module){FreeLibrary(static_cast<HMODULE>(module));}
static const char* dlerror(){return "test library load failed";}
static void setenv(const char* name,const char* value,int){_putenv_s(name,value);SetEnvironmentVariableA(name,value);}
#define RTLD_LOCAL 0
#define RTLD_NOW 0
#else
#include <dlfcn.h>
#include <sys/stat.h>
#endif
#include <filesystem>
#include <iostream>
#include <string>
#include <thread>
#include <array>
#include <vector>
#include <cstring>
#include <stdexcept>
#include <chrono>
using Bytes=std::vector<unsigned char>;
static unsigned checks=0;
static void check(bool condition,const char* message){++checks;if(!condition)throw std::runtime_error(message);}
int main(int argc,char** argv){try{
    check(argc==2,"test module required");
    auto root=std::filesystem::temp_directory_path()/("cie-linux-pkcs11-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    check(std::filesystem::create_directory(root),"isolated directory");
#ifndef _WIN32
    // POSIX permissions only. A global Windows shim conflicts with MinGW's
    // real chmod declaration pulled in by <filesystem>.
    chmod(root.string().c_str(),0700);
#endif
    struct Cleanup {std::filesystem::path path;~Cleanup(){std::error_code e;std::filesystem::remove_all(path,e);}} cleanup{root};
    setenv("CIE_PAIRING_TEST_CACHE",root.string().c_str(),1);
    auto module=dlopen(argv[1],RTLD_LOCAL|RTLD_NOW);if(!module)throw std::runtime_error(dlerror());
    auto get=reinterpret_cast<CK_C_GetFunctionList>(dlsym(module,"C_GetFunctionList"));
    auto metric=reinterpret_cast<unsigned(*)(unsigned)>(dlsym(module,"CieTestMetric"));
    auto control=reinterpret_cast<void(*)(unsigned,unsigned)>(dlsym(module,"CieTestControl"));
    auto expire=reinterpret_cast<void(*)()>(dlsym(module,"CieTestExpire"));
    check(get&&metric&&control&&expire,"test-only module loaded");control(0,0);
    CK_FUNCTION_LIST_PTR f=nullptr;check(get(&f)==CKR_OK&&f&&f->version.major==2,"PKCS11 function table");
    check(get(nullptr)==CKR_ARGUMENTS_BAD,"null function-list output");
    CK_INFO info{};check(f->C_GetInfo(&info)==CKR_CRYPTOKI_NOT_INITIALIZED,"initialization required");
    CK_C_INITIALIZE_ARGS args{};args.pReserved=&args;
    check(f->C_Initialize(&args)==CKR_ARGUMENTS_BAD,"reserved initialization data rejected");
    check(f->C_Initialize(nullptr)==CKR_OK,"initialize");
    check(f->C_Initialize(nullptr)==CKR_CRYPTOKI_ALREADY_INITIALIZED,"duplicate initialize");
    check(f->C_GetInfo(&info)==CKR_OK,"module info");
    check(std::string(reinterpret_cast<char*>(info.manufacturerID),13)=="Firma con CIE","public module name");
    CK_ULONG count=0;check(f->C_GetSlotList(CK_TRUE,nullptr,&count)==CKR_OK&&count==1,"synthetic slot count");
    CK_SLOT_ID slot=0;count=0;check(f->C_GetSlotList(CK_TRUE,&slot,&count)==CKR_BUFFER_TOO_SMALL&&count==1,"slot short buffer");
    check(f->C_GetSlotList(CK_TRUE,&slot,&count)==CKR_OK&&slot,"stable slot");
    CK_TOKEN_INFO token{};check(f->C_GetTokenInfo(slot,&token)==CKR_OK,"public token discovery");
    check(token.ulMinPinLen==8&&token.ulMaxPinLen==8&&(token.flags&CKF_LOGIN_REQUIRED),"full PIN contract");
    check(metric(2)==0&&metric(3)==0,"discovery never authenticates/signs");
    check(metric(7)==metric(8)&&metric(9)==1,"discovery transaction released/reset");
    CK_MECHANISM_TYPE mechanisms[8]{};count=8;
    check(f->C_GetMechanismList(slot,mechanisms,&count)==CKR_OK&&count==7,"RSA and public SHA2 mechanisms");
    for(unsigned i=0;i<count;++i)check(mechanisms[i]!=CKM_RSA_PKCS_PSS&&mechanisms[i]!=CKM_SHA1_RSA_PKCS,"no PSS/SHA1 advertisement");
    CK_SESSION_HANDLE session=0,second=0;
    check(f->C_OpenSession(slot,0,nullptr,nullptr,&session)==CKR_SESSION_PARALLEL_NOT_SUPPORTED,"serial sessions required");
    check(f->C_OpenSession(slot,CKF_SERIAL_SESSION|CKF_RW_SESSION,nullptr,nullptr,&session)==CKR_TOKEN_WRITE_PROTECTED,"read-only token");
    auto open=[&](){CK_SESSION_HANDLE h=0;check(f->C_OpenSession(slot,CKF_SERIAL_SESSION,nullptr,nullptr,&h)==CKR_OK,"open session");return h;};
    session=open();second=open();
    auto attribute=[&](CK_OBJECT_HANDLE object,CK_ATTRIBUTE_TYPE type){
        CK_ATTRIBUTE a{type,nullptr,0};check(f->C_GetAttributeValue(session,object,&a,1)==CKR_OK,"attribute size");
        Bytes value(a.ulValueLen);a.pValue=value.data();check(f->C_GetAttributeValue(session,object,&a,1)==CKR_OK,"attribute value");return value;
    };
    check(f->C_FindObjectsInit(session,nullptr,0)==CKR_OK,"start object search");
    CK_OBJECT_HANDLE objects[8]{};count=0;
    check(f->C_FindObjects(session,objects,8,&count)==CKR_OK&&count==3,"certificate/public/private objects");
    check(f->C_FindObjectsFinal(session)==CKR_OK,"finish search");
    check(attribute(1,CKA_ID)==attribute(3,CKA_ID),"matching certificate/key IDs");
    check(attribute(3,CKA_SIGN)==Bytes{1}&&attribute(3,CKA_EXTRACTABLE)==Bytes{0},"one-byte bool attributes");
    auto der=attribute(1,CKA_VALUE);const unsigned char* cursor=der.data();auto cert=d2i_X509(nullptr,&cursor,long(der.size()));
    check(cert!=nullptr,"public certificate DER");auto publicKey=X509_get_pubkey(cert);X509_free(cert);
    unsigned char identityHash[32]{};unsigned identityLength=0;
    check(EVP_Digest(der.data(),der.size(),identityHash,&identityLength,EVP_sha256(),nullptr)==1&&identityLength==32,"certificate identity hash");
    std::string expectedSerial;constexpr char hex[]="0123456789abcdef";
    for(unsigned i=0;i<8;++i){expectedSerial+=hex[identityHash[i]>>4];expectedSerial+=hex[identityHash[i]&15];}
    check(std::string(reinterpret_cast<char*>(token.serialNumber),16)==expectedSerial,"serial is unchanged by the public name");
    check(std::string(reinterpret_cast<char*>(token.label),30)=="Firma con CIE "+expectedSerial,"public token label");
    struct FreeKey {EVP_PKEY* p;~FreeKey(){EVP_PKEY_free(p);}} freeKey{publicKey};
    const unsigned char hashMessage[]="public software operation";
    for(auto mechanism:{CKM_SHA256,CKM_SHA384,CKM_SHA512}) {
      CK_MECHANISM m{CK_MECHANISM_TYPE(mechanism),nullptr,0};
      auto beforeAuth=metric(2),beforeSigns=metric(3);
      check(f->C_DigestInit(session,&m)==CKR_OK,"public digest init without login");
      check(f->C_DigestInit(session,&m)==CKR_OPERATION_ACTIVE,"digest state is not overwritten");
      CK_ULONG n=0;auto data=const_cast<unsigned char*>(hashMessage);
      check(f->C_Digest(session,data,sizeof(hashMessage)-1,nullptr,&n)==CKR_OK,"public digest length query");
      auto expectedSize=mechanism==CKM_SHA256?32UL:mechanism==CKM_SHA384?48UL:64UL;
      check(n==expectedSize,"SHA2 digest length");Bytes output(n);n=1;
      check(f->C_Digest(session,data,sizeof(hashMessage)-1,output.data(),&n)==CKR_BUFFER_TOO_SMALL&&n==expectedSize,"digest small buffer preserves state");
      check(f->C_Digest(session,data,sizeof(hashMessage)-1,output.data(),&n)==CKR_OK,"single digest");
      const EVP_MD* md=mechanism==CKM_SHA256?EVP_sha256():mechanism==CKM_SHA384?EVP_sha384():EVP_sha512();
      Bytes expected(64);unsigned length=0;EVP_Digest(data,sizeof(hashMessage)-1,expected.data(),&length,md,nullptr);expected.resize(length);
      check(output==expected,"digest matches independent OpenSSL result");
      check(f->C_DigestFinal(session,output.data(),&n)==CKR_OPERATION_NOT_INITIALIZED,"digest result is consumed");
      check(f->C_DigestInit(session,&m)==CKR_OK,"multipart public digest init");
      check(f->C_DigestUpdate(session,data,5)==CKR_OK&&f->C_DigestUpdate(session,data+5,sizeof(hashMessage)-6)==CKR_OK,"multipart digest updates");
      n=0;check(f->C_DigestFinal(session,nullptr,&n)==CKR_OK&&n==expectedSize,"digest final length query");
      check(f->C_DigestFinal(session,output.data(),&n)==CKR_OK&&output==expected,"multipart matches single digest");
      check(metric(2)==beforeAuth&&metric(3)==beforeSigns,"public digest never authenticates or signs");
    }
    CK_ATTRIBUTE secret{CKA_PRIVATE_EXPONENT,nullptr,0};
    check(f->C_GetAttributeValue(session,3,&secret,1)==CKR_ATTRIBUTE_SENSITIVE&&secret.ulValueLen==CK_UNAVAILABLE_INFORMATION,"private material inaccessible");
    CK_ATTRIBUTE mixed[2]={{CKA_LABEL,nullptr,0},{0x7fffffff,nullptr,0}};
    check(f->C_GetAttributeValue(session,1,mixed,2)==CKR_ATTRIBUTE_TYPE_INVALID&&mixed[0].ulValueLen>0&&mixed[1].ulValueLen==CK_UNAVAILABLE_INFORMATION,"mixed attribute queries");
    unsigned char small=0;CK_ATTRIBUTE shortAttr{CKA_MODULUS,&small,1};
    check(f->C_GetAttributeValue(session,2,&shortAttr,1)==CKR_BUFFER_TOO_SMALL,"attribute short buffer");
    CK_OBJECT_CLASS privateClass=CKO_PRIVATE_KEY;CK_ATTRIBUTE filter{CKA_CLASS,&privateClass,sizeof(privateClass)};
    check(f->C_FindObjectsInit(session,&filter,1)==CKR_OK,"filtered search");
    check(f->C_FindObjects(session,objects,8,&count)==CKR_OK&&count==1&&objects[0]==3,"private key class filter");
    check(f->C_FindObjectsFinal(session)==CKR_OK,"finish filtered search");
    CK_MECHANISM raw{CKM_RSA_PKCS,nullptr,0};
    check(f->C_SignInit(session,&raw,3)==CKR_USER_NOT_LOGGED_IN,"no sign before login");
    unsigned char pin[]="12345678",suffix[]="5678",invalid[]="1234a678",wrong[]="00000000";
    check(f->C_Login(session,CKU_USER,suffix,4)==CKR_PIN_LEN_RANGE,"partial PIN rejected");
    check(f->C_Login(session,CKU_USER,invalid,8)==CKR_PIN_INVALID,"nondigit PIN rejected");
    check(f->C_Login(session,CKU_SO,pin,8)==CKR_USER_TYPE_INVALID,"SO login rejected");
    check(metric(2)==0,"invalid PINs never reach engine");
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_OK,"full PIN accepted");
    check(metric(2)==1&&!std::memcmp(pin,"12345678",8),"one verify; caller buffer belongs to caller");
    CK_SESSION_INFO sessionInfo{};
    check(f->C_GetSessionInfo(second,&sessionInfo)==CKR_OK&&sessionInfo.state==CKS_RO_USER_FUNCTIONS,"token login shared across NSS sessions");
    check(f->C_Login(second,CKU_USER,pin,8)==CKR_USER_ALREADY_LOGGED_IN&&metric(2)==1,"duplicate login does not verify");
    CK_MECHANISM pss{CKM_RSA_PKCS_PSS,nullptr,0};
    check(f->C_SignInit(session,&pss,3)==CKR_MECHANISM_INVALID,"PSS rejected");
    auto encoded=[](){Bytes out={0x30,0x31,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,1,0x65,3,4,2,1,5,0,4,32};out.resize(51,0x42);return out;}();
    auto verify=[&](const Bytes& digest,const Bytes& signature){
        auto ctx=EVP_PKEY_CTX_new(publicKey,nullptr);
        bool ok=ctx&&EVP_PKEY_verify_init(ctx)>0&&EVP_PKEY_CTX_set_rsa_padding(ctx,RSA_PKCS1_PADDING)>0&&EVP_PKEY_verify(ctx,signature.data(),signature.size(),digest.data(),digest.size())==1;
        EVP_PKEY_CTX_free(ctx);check(ok,"signature verifies against exposed certificate");
    };
    check(f->C_SignInit(session,&raw,3)==CKR_OK,"sign init");
    CK_ULONG size=0;check(f->C_Sign(session,encoded.data(),encoded.size(),nullptr,&size)==CKR_OK&&size==256&&metric(3)==0,"size query has no private operation");
    Bytes signature(256);size=1;
    check(f->C_Sign(session,encoded.data(),encoded.size(),signature.data(),&size)==CKR_BUFFER_TOO_SMALL&&size==256&&metric(3)==0,"small buffer does not sign or terminate");
    check(f->C_Sign(session,encoded.data(),encoded.size(),signature.data(),&size)==CKR_OK&&metric(3)==1,"single real synthetic signature");verify(encoded,signature);
    auto firstSignature=signature;
    check(f->C_Sign(session,encoded.data(),encoded.size(),signature.data(),&size)==CKR_OPERATION_NOT_INITIALIZED,"signature cannot be replayed");
    check(f->C_SignInit(session,&raw,3)==CKR_OK,"raw rejection init");Bytes arbitrary(32,0x42);
    check(f->C_Sign(session,arbitrary.data(),arbitrary.size(),signature.data(),&size)==CKR_DATA_INVALID&&metric(3)==1,"arbitrary RSA input rejected before signing");
    check(f->C_SignInit(session,&raw,3)==CKR_OK,"invalid arguments sign init");
    check(f->C_Sign(session,nullptr,1,signature.data(),&size)==CKR_ARGUMENTS_BAD,"invalid signing arguments rejected");
    check(f->C_Sign(session,encoded.data(),encoded.size(),signature.data(),&size)==CKR_OPERATION_NOT_INITIALIZED,"invalid arguments end the operation");
    const unsigned char message[]="synthetic NSS TLS request";
    std::vector<std::pair<CK_MECHANISM_TYPE,Bytes>> signedMessages;
    for(auto mechanism:{CKM_SHA256_RSA_PKCS,CKM_SHA384_RSA_PKCS,CKM_SHA512_RSA_PKCS}) {
        CK_MECHANISM m{CK_MECHANISM_TYPE(mechanism),nullptr,0};
        check(f->C_SignInit(second,&m,3)==CKR_OK,"multipart init");
        check(f->C_SignUpdate(second,const_cast<unsigned char*>(message),5)==CKR_OK,"multipart first part");
        check(f->C_SignUpdate(second,const_cast<unsigned char*>(message)+5,sizeof(message)-6)==CKR_OK,"multipart second part");
        size=0;auto before=metric(3);check(f->C_SignFinal(second,nullptr,&size)==CKR_OK&&size==256&&metric(3)==before,"multipart length query");
        size=256;check(f->C_SignFinal(second,signature.data(),&size)==CKR_OK&&metric(3)==before+1,"multipart signature");
        const EVP_MD* md=mechanism==CKM_SHA256_RSA_PKCS?EVP_sha256():mechanism==CKM_SHA384_RSA_PKCS?EVP_sha384():EVP_sha512();
        unsigned n=0;Bytes digest(64);EVP_Digest(message,sizeof(message)-1,digest.data(),&n,md,nullptr);digest.resize(n);
        Bytes dg={0x30,uint8_t(17+n),0x30,0x0d,0x06,0x09,0x60,0x86,0x48,1,0x65,3,4,2,uint8_t(n==32?1:n==48?2:3),5,0,4,uint8_t(n)};
        dg.insert(dg.end(),digest.begin(),digest.end());verify(dg,signature);signedMessages.push_back({m.mechanism,signature});
    }
    auto auths=metric(2);check(auths==1,"multiple signatures do not resend PIN");
    check(f->C_SetPIN(session,pin,8,pin,8)==CKR_FUNCTION_NOT_SUPPORTED,"PIN mutation disabled");
    check(f->C_InitToken(slot,pin,8,nullptr)==CKR_FUNCTION_NOT_SUPPORTED,"token initialization disabled");
    check(f->C_DecryptInit(session,&raw,3)==CKR_FUNCTION_NOT_SUPPORTED,"decryption disabled");
    expire();check(f->C_GetSessionInfo(session,&sessionInfo)==CKR_OK&&sessionInfo.state==CKS_RO_PUBLIC_SESSION,"idle expiry releases authentication");
    check(metric(7)==metric(8),"idle expiry balances transactions");
    check(metric(2)==auths,"expiry never reauthenticates automatically");
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_OK&&metric(2)==auths+1,"new explicit full-PIN login after expiry");
    check(f->C_Logout(session)==CKR_OK,"explicit logout");
    auto publicAuths=metric(2),publicSigns=metric(3);
    check(f->C_VerifyInit(session,&raw,3)==CKR_KEY_HANDLE_INVALID,"verification rejects a private key handle");
    check(f->C_VerifyInit(session,&raw,2)==CKR_OK,"public verification without login");
    check(f->C_Verify(session,encoded.data(),static_cast<CK_ULONG>(encoded.size()),firstSignature.data(),256)==CKR_OK,"raw DigestInfo signature verified");
    auto corrupt=firstSignature;corrupt[0]^=1;
    check(f->C_VerifyInit(session,&raw,2)==CKR_OK,"invalid signature init");
    check(f->C_Verify(session,encoded.data(),static_cast<CK_ULONG>(encoded.size()),corrupt.data(),256)==CKR_SIGNATURE_INVALID,"tampered signature rejected");
    check(f->C_VerifyInit(session,&raw,2)==CKR_OK,"short signature init");
    check(f->C_Verify(session,encoded.data(),static_cast<CK_ULONG>(encoded.size()),firstSignature.data(),255)==CKR_SIGNATURE_LEN_RANGE,"short signature rejected");
    for(auto& entry:signedMessages){
      CK_MECHANISM m{entry.first,nullptr,0};auto data=const_cast<unsigned char*>(message);
      check(f->C_VerifyInit(session,&m,2)==CKR_OK,"hashed verification init");
      check(f->C_Verify(session,data,sizeof(message)-1,entry.second.data(),256)==CKR_OK,"hashed signature verification");
      check(f->C_VerifyInit(session,&m,2)==CKR_OK,"multipart verification init");
      check(f->C_VerifyUpdate(session,data,5)==CKR_OK&&f->C_VerifyUpdate(session,data+5,sizeof(message)-6)==CKR_OK,"multipart verification updates");
      check(f->C_VerifyFinal(session,entry.second.data(),256)==CKR_OK,"multipart signature verification");
      check(f->C_VerifyFinal(session,entry.second.data(),256)==CKR_OPERATION_NOT_INITIALIZED,"verification is consumed");
    }
    check(metric(2)==publicAuths&&metric(3)==publicSigns,"public verification never authenticates or signs");
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_OK&&metric(2)==auths+2,"explicit login after logout");
    auths=metric(2);
    check(f->C_CloseAllSessions(slot)==CKR_OK,"close expired sessions");session=open();
    check(f->C_Login(session,CKU_USER,wrong,8)==CKR_PIN_INCORRECT,"wrong synthetic PIN mapped");
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_USER_NOT_LOGGED_IN&&metric(2)==auths+1,"failed authentication terminal without retry");
    check(f->C_CloseAllSessions(slot)==CKR_OK,"close failed session");session=open();control(6,1);
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_PIN_LOCKED,"locked synthetic PIN mapped");control(6,0);
    check(f->C_CloseAllSessions(slot)==CKR_OK,"close locked session");session=open();control(2,1);auths=metric(2);
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_DEVICE_ERROR&&metric(2)==auths,"changed identity rejected before PIN");control(2,0);
    check(f->C_CloseAllSessions(slot)==CKR_OK,"close changed session");session=open();control(3,1);
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_DEVICE_ERROR&&metric(2)==auths,"busy reader never retried");control(3,0);
    check(f->C_CloseAllSessions(slot)==CKR_OK,"close busy session");session=open();
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_OK,"new explicit session login");
    check(f->C_SignInit(session,&raw,3)==CKR_OK,"transport-failure sign init");control(4,1);size=256;auths=metric(2);
    check(f->C_Sign(session,encoded.data(),encoded.size(),signature.data(),&size)==CKR_DEVICE_ERROR,"transport failure terminates signing");control(4,0);
    check(f->C_SignInit(session,&raw,3)==CKR_USER_NOT_LOGGED_IN&&metric(2)==auths,"transport failure has no recovery authentication");
    check(f->C_CloseAllSessions(slot)==CKR_OK,"close transport session");session=open();
    check(f->C_Login(session,CKU_USER,pin,8)==CKR_OK,"login before removal");control(1,0);count=8;
    check(f->C_GetSlotList(CK_TRUE,objects,&count)==CKR_OK&&count==0,"card removal updates presence");
    check(f->C_GetSessionInfo(session,&sessionInfo)==CKR_DEVICE_REMOVED,"removed token invalidates old sessions");
    check(f->C_CloseSession(session)==CKR_OK,"removed session can close");control(1,1);count=1;
    check(f->C_GetSlotList(CK_TRUE,&slot,&count)==CKR_OK&&count==1,"reinsertion retains slot");
    check(f->C_CloseSession(999999)==CKR_SESSION_HANDLE_INVALID,"invalid session handle");
    std::array<std::thread,4> threads;
    for(auto& thread:threads)thread=std::thread([&]{for(unsigned i=0;i<50;++i){CK_INFO value{};if(f->C_GetInfo(&value)!=CKR_OK)std::terminate();}});
    for(auto& thread:threads)thread.join();
    check(true,"concurrent NSS reads serialized");
    check(f->C_Finalize(nullptr)==CKR_OK,"finalize");check(metric(7)==metric(8),"all transactions released");
    check(f->C_Finalize(nullptr)==CKR_CRYPTOKI_NOT_INITIALIZED,"duplicate finalize");
    check(f->C_Initialize(nullptr)==CKR_OK&&f->C_Finalize(nullptr)==CKR_OK,"clean reinitialization");
    check(metric(11)==0,"fake engine never reaches PCSC transmit");
    dlclose(module);check(!std::filesystem::exists(root/"cache-v3"),"read-only discovery creates no cache");
    std::cout<<"{\"passed\":true,\"checks\":"<<checks<<",\"realCardOperations\":0,\"browserConfigurationChanged\":false}\n";return 0;
}catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}}
