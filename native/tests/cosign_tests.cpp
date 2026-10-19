// SPDX-License-Identifier: BSD-3-Clause
#include "Native/CadesCosign.h"
#include "SignatureGenerator.h"
#include <openssl/cms.h>
#include <openssl/rsa.h>
#include <openssl/x509v3.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
using cie::cades::Bytes;
static unsigned checks=0;
static void check(bool v,const char* message){++checks;if(!v)throw std::runtime_error(message);}
struct Identity{
 EVP_PKEY* key=nullptr;X509* cert=nullptr;
 Identity(int serial){auto ctx=EVP_PKEY_CTX_new_from_name(nullptr,"RSA",nullptr);check(ctx&&EVP_PKEY_keygen_init(ctx)>0&&EVP_PKEY_CTX_set_rsa_keygen_bits(ctx,2048)>0&&EVP_PKEY_keygen(ctx,&key)>0,"Test key");EVP_PKEY_CTX_free(ctx);cert=X509_new();X509_set_version(cert,2);ASN1_INTEGER_set(X509_get_serialNumber(cert),serial);X509_gmtime_adj(X509_getm_notBefore(cert),-60);X509_gmtime_adj(X509_getm_notAfter(cert),3600);X509_set_pubkey(cert,key);X509_NAME_add_entry_by_txt(X509_get_subject_name(cert),"CN",MBSTRING_ASC,reinterpret_cast<const unsigned char*>("Synthetic co-sign test"),-1,-1,0);X509_set_issuer_name(cert,X509_get_subject_name(cert));check(X509_sign(cert,key,EVP_sha256())>0,"Test certificate");}
 ~Identity(){X509_free(cert);EVP_PKEY_free(key);}
};
class MemorySigner:public CBaseSigner{
 Identity& identity;
 public:int calls=0;explicit MemorySigner(Identity& id):identity(id){}
 long GetCertificate(const char*,CCertificate** out,UUCByteArray&)override{int n=i2d_X509(identity.cert,nullptr);Bytes bytes(n);auto* p=bytes.data();i2d_X509(identity.cert,&p);*out=new CCertificate(bytes.data(),bytes.size());return 0;}
 long Sign(UUCByteArray& data,UUCByteArray&,int mechanism,UUCByteArray& out)override{++calls;check(mechanism==CKM_RSA_PKCS,"Unexpected mechanism");auto ctx=EVP_PKEY_CTX_new(identity.key,nullptr);size_t n=0;check(ctx&&EVP_PKEY_sign_init(ctx)>0&&EVP_PKEY_CTX_set_rsa_padding(ctx,RSA_PKCS1_PADDING)>0&&EVP_PKEY_sign(ctx,nullptr,&n,data.getContent(),data.getLength())>0,"Memory sign init");Bytes bytes(n);check(EVP_PKEY_sign(ctx,bytes.data(),&n,data.getContent(),data.getLength())>0,"Memory sign");EVP_PKEY_CTX_free(ctx);out.removeAll();out.append(bytes.data(),n);return 0;}
 long Close()override{return 0;}
};
static Bytes initial(Identity& one,Identity& two,const Bytes& data,bool detached=false,const EVP_MD* digest=EVP_sha384()){
 auto cms=CMS_sign(nullptr,nullptr,nullptr,nullptr,CMS_BINARY|CMS_PARTIAL|(detached?CMS_DETACHED:0));check(cms,"CMS init");
 auto si=CMS_add1_signer(cms,one.cert,one.key,digest,0);check(si&&CMS_add1_signer(cms,two.cert,two.key,EVP_sha256(),0),"Two existing signers");
 auto oid=OBJ_txt2obj("1.2.3.4.5.6.7.8",1);const unsigned char attr[]={1,2,3};check(CMS_unsigned_add1_attr_by_OBJ(si,oid,V_ASN1_OCTET_STRING,attr,sizeof(attr))==1,"Unsigned attribute");ASN1_OBJECT_free(oid);
 X509_CRL* crl=X509_CRL_new();X509_CRL_set_version(crl,1);X509_CRL_set_issuer_name(crl,X509_get_subject_name(one.cert));auto now=ASN1_TIME_new();ASN1_TIME_set(now,time(nullptr));X509_CRL_set1_lastUpdate(crl,now);ASN1_TIME_set(now,time(nullptr)+3600);X509_CRL_set1_nextUpdate(crl,now);ASN1_TIME_free(now);check(X509_CRL_sign(crl,one.key,EVP_sha256())>0&&CMS_add1_crl(cms,crl)==1,"Embedded CRL");X509_CRL_free(crl);
 auto bio=BIO_new_mem_buf(data.data(),data.size());check(CMS_final(cms,bio,nullptr,CMS_BINARY|(detached?CMS_DETACHED:0))==1,"CMS final");BIO_free(bio);int n=i2d_CMS_ContentInfo(cms,nullptr);Bytes bytes(n);auto p=bytes.data();i2d_CMS_ContentInfo(cms,&p);CMS_ContentInfo_free(cms);return bytes;
}
int main(int argc,char**argv){try{
 Identity first(1),second(2),third(3);const Bytes data={'C','I','E',' ','c','o','s','i','g','n'};auto original=initial(first,second,data);auto canonical=cie::cades::canonical(original.data(),original.size());
 Bytes encoded(4*((original.size()+2)/3)+1);int encodedLength=EVP_EncodeBlock(encoded.data(),original.data(),original.size());encoded.resize(encodedLength);auto base64=cie::cades::canonical(encoded.data(),encoded.size());check(base64==canonical,"Base64 co-sign input");
 std::string pem="-----BEGIN PKCS7-----\n"+std::string(encoded.begin(),encoded.end())+"\n-----END PKCS7-----\n";check(cie::cades::canonical(pem.data(),pem.size())==canonical,"PEM co-sign input");
 check(cie::cades::count(canonical)==2,"Original count");
 MemorySigner signer(third);CSignatureGenerator generator(&signer);generator.SetCAdES(true);generator.SetPKCS7Data(UUCByteArray(original.data(),original.size()));UUCByteArray result;check(generator.Generate(result,FALSE,FALSE)==0,"SDK co-sign failed");Bytes combined(result.getContent(),result.getContent()+result.getLength());auto checked=cie::cades::canonical(combined.data(),combined.size());check(cie::cades::count(checked)==3,"Must add exactly one signer");check(cie::cades::preserves(canonical,checked),"Original signers/certificates/CRL/content lost");check(cie::cades::content(checked)==data,"Nested CMS or changed content");check(signer.calls==1,"Signer retry");
 CSignedDocument verified(combined.data(),combined.size());for(int i=0;i<3;i++){int status=verified.verify(i,static_cast<REVOCATION_INFO*>(nullptr));check(status>=0 && (status&VERIFIED_SIGNATURE)!=0,"SDK verifier rejected a co-signature");}
 auto sha512=initial(first,second,data,false,EVP_sha512());CSignedDocument verified512(sha512.data(),sha512.size());for(int i=0;i<2;i++){int status=verified512.verify(i,static_cast<REVOCATION_INFO*>(nullptr));check(status>=0 && (status&VERIFIED_SIGNATURE)!=0,"SDK verifier rejected SHA-512");}
 for(auto bad:{Bytes{'b','a','d'},initial(first,second,data,true)}){MemorySigner blocked(third);CSignatureGenerator g(&blocked);bool rejected=false;try{g.SetPKCS7Data(UUCByteArray(bad.data(),bad.size()));}catch(...){rejected=true;}check(rejected&&blocked.calls==0,"Invalid/detached CMS reached signer");}
 auto damaged=original;const unsigned char* cursor=damaged.data();auto tampered=d2i_CMS_ContentInfo(nullptr,&cursor,damaged.size());auto sig=CMS_SignerInfo_get0_signature(sk_CMS_SignerInfo_value(CMS_get0_SignerInfos(tampered),0));const_cast<unsigned char*>(ASN1_STRING_get0_data(sig))[0]^=1;damaged.resize(i2d_CMS_ContentInfo(tampered,nullptr));auto target=damaged.data();i2d_CMS_ContentInfo(tampered,&target);CMS_ContentInfo_free(tampered);bool rejected=false;try{cie::cades::canonical(damaged.data(),damaged.size());}catch(...){rejected=true;}check(rejected,"Invalid original signature accepted");
 if(argc>1){auto path=std::filesystem::u8path(argv[1]);std::filesystem::create_directories(path);for(auto pair:{std::make_pair("original-two.p7m",original),std::make_pair("cofirmato-three.p7m",combined)}){std::ofstream f(path/pair.first,std::ios::binary);f.write(reinterpret_cast<const char*>(pair.second.data()),pair.second.size());}}
 std::cout<<"COSIGN_CHECKS="<<checks<<"\nTwo original signatures, mixed digest algorithms, unsigned attribute and CRL preserved; one new SDK signature; no card accessed\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
