// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "Native/Digest.h"
#include <openssl/core_names.h>
#include "Native/RsaRecovery.h"
#include "ASN1/ByteReader.h"
#include "ASN1/Asn1Errors.h"
#include "SignatureGenerator.h"
#include "../../native/PropertyTable.h"
#include <iomanip>
#include <sstream>

static std::string hexBytes(const unsigned char* data, size_t size) {
    std::ostringstream result;
    for (size_t i=0; i<size; ++i) result << std::hex << std::setw(2) << std::setfill('0') << unsigned(data[i]);
    return result.str();
}
static void testNativeDigests() {
    const unsigned char* abc = reinterpret_cast<const unsigned char*>("abc");
    unsigned char bytes[32];
    cie::digestSHA2(abc,3,bytes,0);
    require(hexBytes(bytes,32)=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 known vector");
    cie::digestSHA2(abc,3,bytes,1);
    require(hexBytes(bytes,28)=="23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7", "SHA-224 known vector");
    cie::Sha1Digest hash;
    hash.update(abc,1); hash.update(abc+1,2); hash.finish();
    require(hash.words == std::array<unsigned int,5>{{0xa9993e36,0x4706816a,0xba3e2571,0x7850c26c,0x9cd0d89d}}, "SHA-1 known vector");
    hash.finish();
    bool rejected=false;
    try { hash.update(abc,1); } catch(const std::invalid_argument&) { rejected=true; }
    require(rejected,"SHA-1 update after finish must fail");
    hash.reset(); hash.update(nullptr,0); hash.finish();
    require(hash.words == std::array<unsigned int,5>{{0xda39a3ee,0x5e6b4b0d,0x3255bfef,0x95601890,0xafd80709}}, "Empty SHA-1 vector");
    std::vector<unsigned char> chunk(1000,'a'); hash.reset();
    for(int i=0;i<1000;++i) hash.update(chunk.data(),chunk.size());
    hash.finish();
    require(hash.words == std::array<unsigned int,5>{{0x34aa973c,0xd4c4daa4,0xf61eeb2b,0xdbad2731,0x6534016f}}, "Million a SHA-1 vector");
}
static std::vector<unsigned char> rawRsaSign(EVP_PKEY* key,const unsigned char* data,size_t length) {
    std::unique_ptr<EVP_PKEY_CTX,decltype(&EVP_PKEY_CTX_free)> ctx(EVP_PKEY_CTX_new_from_pkey(nullptr,key,nullptr),EVP_PKEY_CTX_free);
    require(ctx && EVP_PKEY_sign_init(ctx.get())==1 && EVP_PKEY_CTX_set_rsa_padding(ctx.get(),RSA_PKCS1_PADDING)==1,"RSA sign init");
    size_t size=0;
    require(EVP_PKEY_sign(ctx.get(),nullptr,&size,data,length)==1,"RSA sign size");
    std::vector<unsigned char> result(size);
    require(EVP_PKEY_sign(ctx.get(),result.data(),&size,data,length)==1,"RSA sign"); result.resize(size); return result;
}
static void testRsaRecovery(EVP_PKEY* key) {
    BIGNUM *rawN=nullptr,*rawE=nullptr;
    require(EVP_PKEY_get_bn_param(key,OSSL_PKEY_PARAM_RSA_N,&rawN)==1 &&
            EVP_PKEY_get_bn_param(key,OSSL_PKEY_PARAM_RSA_E,&rawE)==1,"Provider RSA parameters");
    std::unique_ptr<BIGNUM,decltype(&BN_free)> n(rawN,BN_free),e(rawE,BN_free);
    std::vector<unsigned char> modulus(BN_num_bytes(n.get())), exponent(BN_num_bytes(e.get()));
    BN_bn2bin(n.get(),modulus.data()); BN_bn2bin(e.get(),exponent.data());
    const unsigned char message[]={0x30,0x03,0x04,0x01,0x41};
    auto signature=rawRsaSign(key,message,sizeof(message)); std::vector<unsigned char> output;
    auto recover=[&](size_t length) { return cie::recoverRsaPkcs1(modulus.data(),modulus.size(),exponent.data(),exponent.size(),signature.data(),length,output); };
    require(recover(signature.size()) && output==std::vector<unsigned char>(message,message+sizeof(message)),"RSA recovery payload");
    modulus.insert(modulus.begin(),0);
    require(recover(signature.size()),"ASN.1 modulus leading zero");
    require(!recover(signature.size()-1) && output.empty(),"Truncated signature accepted");
    signature[0]^=0x80;
    require(!recover(signature.size()) && output.empty(),"Corrupted RSA padding accepted");
    ERR_clear_error();
    exponent.assign(1,1);
    require(!recover(signature.size()),"Invalid RSA exponent accepted");
}
static void testNativeUtilities() {
    const BYTE data[]={1,2,3};
    UUCBufferedReader reader(UUCByteArray(data,3)); BYTE output[5]={};
    reader.mark(); require(reader.read(output,1)==1 && output[0]==1,"Reader first byte");
    reader.mark(); reader.read(output,1); reader.reset(); require(reader.getPosition()==1,"Nested checkpoint");
    reader.reset(); require(reader.getPosition()==0,"Outer checkpoint");
    reader.mark(); reader.releaseMark(); reader.setPosition(1); reader.reset(); require(reader.getPosition()==1,"First checkpoint release");
    require(reader.read(output,5)==2 && output[0]==2 && output[1]==3,"Reader truncation");
    bool rejected=false; try { reader.setPosition(4); } catch(const std::out_of_range&) { rejected=true; }
    require(rejected,"Out of range reader position");
    CASN1Exception copy("original"); { CASN1Exception temporary("copy"); copy=temporary; }
    char text[5]; require(copy.GetErrorMessage(text,5) && std::string(text)=="copy","Exception message ownership");
    require(!copy.GetErrorMessage(text,4) && !copy.GetErrorMessage(nullptr,5),"Exception output bounds");
    UUCStringTable table; char k[]="key",v[]="value"; char *kp=k,*vp=v;
    table.put(kp,vp); k[0]='X'; v[0]='X'; char lookup[]="key"; kp=lookup;
    require(table.get(kp,vp) && std::string(vp)=="value","Property ownership");
    table.put(kp,vp); require(table.size()==1,"Borrowed property update");
    char other[]="other",empty[]=""; kp=other;vp=empty;table.put(kp,vp);
    unsigned int count=0; for(POS p=table.getFirstPosition();p;) { p=table.getNextEntry(p,kp,vp); ++count; }
    require(count==2,"Property enumeration"); table.removeAll(); require(table.isEmpty(),"Property clear");
}
class SoftwareSigner : public CBaseSigner {
    EVP_PKEY* key_; X509* certificate_;
public:
    SoftwareSigner(EVP_PKEY* key,X509* certificate):key_(key),certificate_(certificate) {}
    long GetCertificate(const char*,CCertificate** output,UUCByteArray&) override {
        int length=i2d_X509(certificate_,nullptr); std::vector<unsigned char> der(length); unsigned char* p=der.data();
        i2d_X509(certificate_,&p); UUCBufferedReader reader(der.data(),length); *output=new CCertificate(reader); return 0;
    }
    long Sign(UUCByteArray& data,UUCByteArray&,int,UUCByteArray& signature) override {
        auto result=rawRsaSign(key_,data.getContent(),data.getLength()); signature.append(result.data(),result.size()); return 0;
    }
    long Close() override { return 0; }
};
static void testSdkCms(EVP_PKEY* key,X509* certificate) {
    SoftwareSigner signer(key,certificate);
    CCertificate* cert=nullptr; UUCByteArray id; signer.GetCertificate(nullptr,&cert,id);
    std::unique_ptr<CCertificate> owned(cert);
    require(cert->verifySignature(*cert),"Native certificate signature verification");
    for(int algorithm : {CKM_SHA1_RSA_PKCS,CKM_SHA256_RSA_PKCS}) {
        CSignatureGenerator generator(&signer); generator.SetHashAlgo(algorithm);
        const BYTE data[]={'t','e','s','t'}; UUCByteArray input(data,sizeof(data)),result;
        generator.SetData(input); require(generator.Generate(result,TRUE,FALSE)==0,"SDK CMS generation");
        const unsigned char* cursor=result.getContent();
        std::unique_ptr<CMS_ContentInfo,decltype(&CMS_ContentInfo_free)> cms(d2i_CMS_ContentInfo(nullptr,&cursor,result.getLength()),CMS_ContentInfo_free);
        std::unique_ptr<BIO,decltype(&BIO_free)> content(BIO_new_mem_buf(data,sizeof(data)),BIO_free);
        int verified = cms ? CMS_verify(cms.get(),nullptr,nullptr,content.get(),nullptr,CMS_BINARY|CMS_NO_SIGNER_CERT_VERIFY) : 0;
        if (verified != 1) ERR_print_errors_fp(stderr);
        require(verified==1,"SDK CMS SHA-1/SHA-256 signature verify");
    }
}
