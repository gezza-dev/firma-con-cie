// SPDX-License-Identifier: BSD-3-Clause
// Read-only diagnostic for public CA certificates/CRLs. No identity card/PIN.
#include "Native/Revocation.h"
#include "Native/Digest.h"
#include <openssl/pem.h>
#include <openssl/x509v3.h>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <memory>

using Bytes=cie::CertificateBytes;
Bytes read(const char* path) {
    std::ifstream file(path,std::ios::binary);
    return {std::istreambuf_iterator<char>(file),std::istreambuf_iterator<char>()};
}
X509* certificate(const Bytes& bytes) {
    auto* p=bytes.data(); auto* c=d2i_X509(nullptr,&p,long(bytes.size()));
    if(c && p==bytes.data()+bytes.size()) return c;
    X509_free(c); BIO* bio=BIO_new_mem_buf(bytes.data(),int(bytes.size()));
    c=bio ? PEM_read_bio_X509(bio,nullptr,nullptr,nullptr) : nullptr; BIO_free(bio); return c;
}
std::string timeText(const ASN1_TIME* t) {
    std::tm tm{};char out[32]{};
    if(t && ASN1_TIME_to_tm(t,&tm)==1) std::strftime(out,sizeof(out),"%Y-%m-%dT%H:%M:%SZ",&tm);
    return out;
}
int main(int argc,char** argv) {
    if(argc!=4) { std::cerr<<"Usage: cie_trust_probe public-target-ca.pem public-issuer-ca.pem response.crl\n";return 2; }
    if(!cie::initializeOpenSsl()) return 3;
    auto targetBytes=read(argv[1]),issuerBytes=read(argv[2]),response=read(argv[3]);
    if(targetBytes.empty() || issuerBytes.empty() || response.empty() || response.size()>64*1024*1024) return 4;
    std::unique_ptr<X509,decltype(&X509_free)> target(certificate(targetBytes),X509_free),issuer(certificate(issuerBytes),X509_free);
    if(!target || !issuer) return 5;
    const auto* p=response.data();
    std::unique_ptr<X509_CRL,decltype(&X509_CRL_free)> crl(d2i_X509_CRL(nullptr,&p,long(response.size())),X509_CRL_free);
    if(!crl) return 6;
    auto now=std::time(nullptr);REVOCATION_INFO info{};
    int status=cie::verifyCrlResponse(response,target.get(),issuer.get(),&info,now);
    std::unique_ptr<EVP_PKEY,decltype(&EVP_PKEY_free)> key(X509_get_pubkey(issuer.get()),EVP_PKEY_free);
    unsigned char hash[EVP_MAX_MD_SIZE];unsigned int length=0;EVP_Digest(response.data(),response.size(),hash,&length,EVP_sha256(),nullptr);
    std::ostringstream digest;for(unsigned i=0;i<length;++i)digest<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(hash[i]);
    std::cout<<std::boolalpha<<"{\"now\":"<<int64_t(now)<<",\"timeTBytes\":"<<sizeof(std::time_t)
      <<",\"crlBytes\":"<<response.size()<<",\"crlSha256\":\""<<digest.str()<<"\",\"derFullyConsumed\":"<<(p==response.data()+response.size())
      <<",\"issuerCheck\":"<<X509_check_issued(issuer.get(),target.get())
      <<",\"issuerCa\":"<<X509_check_ca(issuer.get())
      <<",\"issuerKeyUsage\":"<<X509_get_key_usage(issuer.get())
      <<",\"issuerNotBeforeCmp\":"<<X509_cmp_time(X509_get0_notBefore(issuer.get()),&now)
      <<",\"issuerNotAfterCmp\":"<<X509_cmp_time(X509_get0_notAfter(issuer.get()),&now)
      <<",\"targetSignatureValid\":"<<(key && X509_verify(target.get(),key.get())==1)
      <<",\"crlIssuerMatches\":"<<(X509_NAME_cmp(X509_CRL_get_issuer(crl.get()),X509_get_subject_name(issuer.get()))==0)
      <<",\"crlSignatureValid\":"<<(key && X509_CRL_verify(crl.get(),key.get())==1)
      <<",\"thisUpdate\":\""<<timeText(X509_CRL_get0_lastUpdate(crl.get()))<<"\",\"nextUpdate\":\""<<timeText(X509_CRL_get0_nextUpdate(crl.get()))
      <<"\",\"delta\":"<<(X509_CRL_get_ext_by_NID(crl.get(),NID_delta_crl,-1)>=0)
      <<",\"issuingDistributionPoint\":"<<(X509_CRL_get_ext_by_NID(crl.get(),NID_issuing_distribution_point,-1)>=0)
      <<",\"criticalExtensionOids\":[";
    bool first=true;for(int i=0;i<X509_CRL_get_ext_count(crl.get()) && i<64;++i) {
        auto* e=X509_CRL_get_ext(crl.get(),i);if(!X509_EXTENSION_get_critical(e))continue;
        char oid[128]{};OBJ_obj2txt(oid,sizeof(oid),X509_EXTENSION_get_object(e),1);
        if(!first)std::cout<<',';first=false;std::cout<<'"'<<oid<<'"';
    }
    std::cout<<"],\"nativeCrlStatus\":"<<status<<"}\n";return 0;
}
