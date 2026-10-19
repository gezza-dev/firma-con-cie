// SPDX-License-Identifier: BSD-3-Clause
#include "Native/Revocation.h"
#include "../../native/OpenSslRuntime.h"
#include <openssl/pem.h>
#include <openssl/x509v3.h>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <cstring>

namespace {
template<class T, void(*Free)(T*)> using Owned = std::unique_ptr<T, decltype(Free)>;
using Cert = Owned<X509, X509_free>;
using Key = Owned<EVP_PKEY, EVP_PKEY_free>;
void check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
Key key()
{
    Owned<EVP_PKEY_CTX, EVP_PKEY_CTX_free> ctx(EVP_PKEY_CTX_new_from_name(nullptr,"RSA",nullptr),EVP_PKEY_CTX_free);
    EVP_PKEY* result = nullptr;
    check(ctx && EVP_PKEY_keygen_init(ctx.get())==1 && EVP_PKEY_CTX_set_rsa_keygen_bits(ctx.get(),2048)==1 && EVP_PKEY_keygen(ctx.get(),&result)==1,"Key fixture");
    return Key(result, EVP_PKEY_free);
}
void extension(X509* certificate, X509* issuer, int nid, const char* value)
{
    X509V3_CTX context{}; X509V3_set_ctx(&context,issuer,certificate,nullptr,nullptr,0);
    Owned<X509_EXTENSION,X509_EXTENSION_free> ext(X509V3_EXT_conf_nid(nullptr,&context,nid,const_cast<char*>(value)),X509_EXTENSION_free);
    check(ext && X509_add_ext(certificate,ext.get(),-1)==1,"Extension fixture");
}
Cert cert(EVP_PKEY* subjectKey, X509* issuer, EVP_PKEY* issuerKey, int serial, bool ca=false, bool responder=false)
{
    Cert result(X509_new(), X509_free); check(bool(result),"Certificate fixture");
    X509_set_version(result.get(),2); ASN1_INTEGER_set(X509_get_serialNumber(result.get()),serial);
    X509_gmtime_adj(X509_getm_notBefore(result.get()),-3600); X509_gmtime_adj(X509_getm_notAfter(result.get()),86400);
    X509_set_pubkey(result.get(),subjectKey);
    std::string name="Security fixture "+std::to_string(serial);
    X509_NAME_add_entry_by_txt(X509_get_subject_name(result.get()),"CN",MBSTRING_ASC,reinterpret_cast<const unsigned char*>(name.c_str()),-1,-1,0);
    X509_set_issuer_name(result.get(), X509_get_subject_name(issuer ? issuer : result.get()));
    extension(result.get(),issuer ? issuer : result.get(),NID_basic_constraints,ca ? "critical,CA:TRUE" : "critical,CA:FALSE");
    extension(result.get(),issuer ? issuer : result.get(),NID_key_usage,ca ? "critical,keyCertSign,cRLSign" : "critical,digitalSignature");
    extension(result.get(),issuer ? issuer : result.get(),NID_subject_key_identifier,"hash");
    if (issuer) extension(result.get(),issuer,NID_authority_key_identifier,"keyid:always");
    if (responder) extension(result.get(),issuer,NID_ext_key_usage,"OCSPSigning");
    check(X509_sign(result.get(),issuerKey ? issuerKey : subjectKey,EVP_sha256())>0,"Certificate signature fixture");
    return result;
}
cie::CertificateBytes encode(X509* certificate)
{
    int size=i2d_X509(certificate,nullptr); cie::CertificateBytes bytes(size); auto* out=bytes.data(); i2d_X509(certificate,&out); return bytes;
}
cie::CertificateBytes ocsp(X509* target, X509* issuer, X509* signer, EVP_PKEY* key,
    int status=V_OCSP_CERTSTATUS_GOOD, int reason=OCSP_REVOKED_STATUS_UNSPECIFIED,
    long start=-30, long end=3600, bool mismatchNonce=false)
{
    Owned<OCSP_CERTID,OCSP_CERTID_free> id(OCSP_cert_to_id(EVP_sha1(),target,issuer),OCSP_CERTID_free);
    Owned<OCSP_BASICRESP,OCSP_BASICRESP_free> basic(OCSP_BASICRESP_new(),OCSP_BASICRESP_free);
    Owned<ASN1_TIME,ASN1_TIME_free> from(ASN1_TIME_adj(nullptr,std::time(nullptr),0,start),ASN1_TIME_free);
    Owned<ASN1_TIME,ASN1_TIME_free> until(ASN1_TIME_adj(nullptr,std::time(nullptr),0,end),ASN1_TIME_free);
    Owned<ASN1_TIME,ASN1_TIME_free> revoked(ASN1_TIME_adj(nullptr,std::time(nullptr),0,-3600),ASN1_TIME_free);
    check(OCSP_basic_add1_status(basic.get(),id.get(),status,reason,status==V_OCSP_CERTSTATUS_REVOKED ? revoked.get() : nullptr,from.get(),until.get())!=nullptr,"OCSP status fixture");
    if (mismatchNonce) { unsigned char nonce[16]={1,2,3}; check(OCSP_basic_add1_nonce(basic.get(),nonce,sizeof(nonce))==1,"Nonce fixture"); }
    check(OCSP_basic_sign(basic.get(),signer,key,EVP_sha256(),nullptr,0)==1,"OCSP signature fixture");
    Owned<OCSP_RESPONSE,OCSP_RESPONSE_free> result(OCSP_response_create(OCSP_RESPONSE_STATUS_SUCCESSFUL,basic.get()),OCSP_RESPONSE_free);
    int length=i2d_OCSP_RESPONSE(result.get(),nullptr); cie::CertificateBytes bytes(length); auto* out=bytes.data(); i2d_OCSP_RESPONSE(result.get(),&out); return bytes;
}
cie::CertificateBytes crl(X509* issuer, EVP_PKEY* key, X509* revokedTarget=nullptr,
    long start=-30, long end=3600, bool delta=false)
{
    Owned<X509_CRL,X509_CRL_free> value(X509_CRL_new(),X509_CRL_free);
    X509_CRL_set_version(value.get(),1); X509_CRL_set_issuer_name(value.get(),X509_get_subject_name(issuer));
    Owned<ASN1_TIME,ASN1_TIME_free> from(ASN1_TIME_adj(nullptr,std::time(nullptr),0,start),ASN1_TIME_free);
    Owned<ASN1_TIME,ASN1_TIME_free> until(ASN1_TIME_adj(nullptr,std::time(nullptr),0,end),ASN1_TIME_free);
    X509_CRL_set1_lastUpdate(value.get(),from.get()); X509_CRL_set1_nextUpdate(value.get(),until.get());
    if (revokedTarget) {
        X509_REVOKED* revoked=X509_REVOKED_new();
        X509_REVOKED_set_serialNumber(revoked,X509_get_serialNumber(revokedTarget));
        X509_REVOKED_set_revocationDate(revoked,from.get());
        check(X509_CRL_add0_revoked(value.get(),revoked)==1,"CRL entry fixture");
    }
    if (delta) {
        Owned<ASN1_INTEGER,ASN1_INTEGER_free> number(ASN1_INTEGER_new(),ASN1_INTEGER_free); ASN1_INTEGER_set(number.get(),1);
        check(X509_CRL_add1_ext_i2d(value.get(),NID_delta_crl,number.get(),1,0)==1,"Delta CRL fixture");
    }
    X509_CRL_sort(value.get()); check(X509_CRL_sign(value.get(),key,EVP_sha256())>0,"CRL signature fixture");
    int length=i2d_X509_CRL(value.get(),nullptr); cie::CertificateBytes bytes(length); auto* out=bytes.data(); i2d_X509_CRL(value.get(),&out); return bytes;
}
}
#include "trust_tests.h"
#include "temporal_tests.h"
int main(int argc,char** argv)
{
    try {
        const unsigned char addresses[][4] = {{127,0,0,1},{10,0,0,1},{172,16,1,1},{192,168,1,1},
            {169,254,1,1},{100,64,0,1},{0,0,0,0},{224,0,0,1},{198,18,0,1},{203,0,113,1}};
        for (auto& address : addresses) check(!cie::publicNetworkAddress(address,4),"reject non-public CRL socket peer");
        const unsigned char public4[] = {8,8,8,8};
        const unsigned char public6[] = {0x26,0x06,0x47,0x00,0x47,0x00,0,0,0,0,0,0,0,0,0x11,0x11};
        const unsigned char loop6[] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1};
        check(cie::publicNetworkAddress(public4,4) && cie::publicNetworkAddress(public6,16) &&
            !cie::publicNetworkAddress(loop6,16),"public CRL peer address policy");
        std::cout<<"PASS CRL actual-peer public-address policy\n";
        check(cie::initializeOpenSsl(),"OpenSSL providers");
        if (argc==3 && std::strcmp(argv[1],"--http")==0) {
            auto response=cie::httpRequest(argv[2],{},nullptr,{});
            std::cout<<"CURL_RESULT="<<response.error<<" HTTP_STATUS="<<response.status<<" BODY_SIZE="<<response.body.size()<<'\n';
            return response.error==CURLE_OK ? 0 : 2;
        }
        auto caKey=key(); auto ca=cert(caKey.get(),nullptr,nullptr,1,true);
        auto leafKey=key(); auto leaf=cert(leafKey.get(),ca.get(),caKey.get(),2);
        auto other=cert(leafKey.get(),ca.get(),caKey.get(),3);
        auto delegatedKey=key();auto delegated=cert(delegatedKey.get(),ca.get(),caKey.get(),4,false,true);
        auto unauthorized=cert(delegatedKey.get(),ca.get(),caKey.get(),5);
        auto wrongKey=key(); auto wrongCa=cert(wrongKey.get(),nullptr,nullptr,6,true);
        Owned<OCSP_REQUEST,OCSP_REQUEST_free> request(OCSP_REQUEST_new(),OCSP_REQUEST_free);
        check(OCSP_request_add0_id(request.get(),OCSP_cert_to_id(EVP_sha1(),leaf.get(),ca.get()))!=nullptr &&
              OCSP_request_add1_nonce(request.get(),nullptr,-1)==1,"OCSP request fixture");
        auto checkOcsp=[&](const cie::CertificateBytes& bytes,int expected,const char* label) {
            REVOCATION_INFO information{};
            int result=cie::verifyOcspResponse(bytes,leaf.get(),ca.get(),request.get(),&information,std::time(nullptr));
            check(result==expected,label); std::cout<<"PASS "<<label<<'\n';
        };
        checkOcsp(ocsp(leaf.get(),ca.get(),ca.get(),caKey.get()),REVOCATION_STATUS_GOOD,"signed issuer OCSP good");
        checkOcsp(ocsp(leaf.get(),ca.get(),delegated.get(),delegatedKey.get()),REVOCATION_STATUS_GOOD,"authorized delegated OCSP good");
        checkOcsp(ocsp(leaf.get(),ca.get(),ca.get(),caKey.get(),V_OCSP_CERTSTATUS_REVOKED),REVOCATION_STATUS_REVOKED,"signed OCSP revoked");
        checkOcsp(ocsp(leaf.get(),ca.get(),ca.get(),caKey.get(),V_OCSP_CERTSTATUS_REVOKED,OCSP_REVOKED_STATUS_CERTIFICATEHOLD),REVOCATION_STATUS_SUSPENDED,"signed OCSP suspended");
        checkOcsp(ocsp(leaf.get(),ca.get(),ca.get(),caKey.get(),V_OCSP_CERTSTATUS_UNKNOWN),REVOCATION_STATUS_UNKNOWN,"signed OCSP unknown");
        checkOcsp(ocsp(other.get(),ca.get(),ca.get(),caKey.get()),REVOCATION_STATUS_UNKNOWN,"reject wrong OCSP certificate identifier");
        checkOcsp(ocsp(leaf.get(),ca.get(),wrongCa.get(),wrongKey.get()),REVOCATION_STATUS_UNKNOWN,"reject wrong OCSP issuer");
        checkOcsp(ocsp(leaf.get(),ca.get(),unauthorized.get(),delegatedKey.get()),REVOCATION_STATUS_UNKNOWN,"reject missing OCSP responder EKU");
        checkOcsp(ocsp(leaf.get(),ca.get(),ca.get(),caKey.get(),V_OCSP_CERTSTATUS_GOOD,-1,-7200,-3600),REVOCATION_STATUS_UNKNOWN,"reject expired OCSP response");
        checkOcsp(ocsp(leaf.get(),ca.get(),ca.get(),caKey.get(),V_OCSP_CERTSTATUS_GOOD,-1,3600,7200),REVOCATION_STATUS_UNKNOWN,"reject future OCSP response");
        checkOcsp(ocsp(leaf.get(),ca.get(),ca.get(),caKey.get(),V_OCSP_CERTSTATUS_GOOD,-1,-30,3600,true),REVOCATION_STATUS_UNKNOWN,"reject mismatching OCSP nonce");
        auto badSignature=ocsp(leaf.get(),ca.get(),ca.get(),caKey.get());
        const unsigned char* badCursor=badSignature.data();
        Owned<OCSP_RESPONSE,OCSP_RESPONSE_free> badResponse(d2i_OCSP_RESPONSE(nullptr,&badCursor,long(badSignature.size())),OCSP_RESPONSE_free);
        Owned<OCSP_BASICRESP,OCSP_BASICRESP_free> badBasic(OCSP_response_get1_basic(badResponse.get()),OCSP_BASICRESP_free);
        auto* signature=const_cast<ASN1_OCTET_STRING*>(OCSP_resp_get0_signature(badBasic.get()));
        check(signature && ASN1_STRING_length(signature)>0,"Signature corruption fixture");
        const_cast<unsigned char*>(ASN1_STRING_get0_data(signature))[0]^=1;
        badResponse.reset(OCSP_response_create(OCSP_RESPONSE_STATUS_SUCCESSFUL,badBasic.get()));
        badSignature.resize(i2d_OCSP_RESPONSE(badResponse.get(),nullptr));auto* badOut=badSignature.data();
        i2d_OCSP_RESPONSE(badResponse.get(),&badOut);
        checkOcsp(badSignature,REVOCATION_STATUS_UNKNOWN,"reject altered OCSP signature");
        auto forged=ocsp(leaf.get(),ca.get(),ca.get(),caKey.get()); forged.resize(forged.size()/2);
        checkOcsp(forged,REVOCATION_STATUS_UNKNOWN,"reject truncated or unsigned OCSP response");
        forged=ocsp(leaf.get(),ca.get(),ca.get(),caKey.get());forged.push_back(0);
        checkOcsp(forged,REVOCATION_STATUS_UNKNOWN,"reject trailing OCSP data");
        auto checkCrl=[&](const cie::CertificateBytes& bytes,int expected,const char* label) {
            REVOCATION_INFO information{};
            int result=cie::verifyCrlResponse(bytes,leaf.get(),ca.get(),&information,std::time(nullptr));
            check(result==expected,label); std::cout<<"PASS "<<label<<'\n';
        };
        checkCrl(crl(ca.get(),caKey.get()),REVOCATION_STATUS_GOOD,"signed complete CRL good");
        checkCrl(crl(ca.get(),caKey.get(),leaf.get()),REVOCATION_STATUS_REVOKED,"signed CRL revoked");
        checkCrl(crl(ca.get(),wrongKey.get()),REVOCATION_STATUS_UNKNOWN,"reject forged CRL signature");
        checkCrl(crl(wrongCa.get(),wrongKey.get()),REVOCATION_STATUS_UNKNOWN,"reject wrong CRL issuer");
        checkCrl(crl(ca.get(),caKey.get(),nullptr,-7200,-3600),REVOCATION_STATUS_UNKNOWN,"reject expired CRL");
        checkCrl(crl(ca.get(),caKey.get(),nullptr,3600,7200),REVOCATION_STATUS_UNKNOWN,"reject future CRL");
        checkCrl(crl(ca.get(),caKey.get(),nullptr,-30,3600,true),REVOCATION_STATUS_UNKNOWN,"reject delta CRL without base");
        check(cie::checkRevocation(encode(leaf.get()),{}, {},nullptr)==REVOCATION_STATUS_UNKNOWN,"Missing issuer must not report good");
        std::cout<<"PASS missing issuer remains unknown\n";
        testCertificateTrust();
        testTemporalValidation(argc==3 && std::strcmp(argv[1],"--temporal-fixtures")==0 ? std::filesystem::u8path(argv[2]) : std::filesystem::path{});
        return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
