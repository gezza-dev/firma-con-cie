// SPDX-License-Identifier: BSD-3-Clause
#include "TemporalValidation.h"
#include "Digest.h"
#include <openssl/cms.h>
#include <openssl/ts.h>
#include <openssl/x509v3.h>
#include <openssl/err.h>
#include <memory>
#include <cstring>
#include <algorithm>
#include <limits>
namespace cie {
namespace {
template<class T, void(*Free)(T*)> using Owned = std::unique_ptr<T, decltype(Free)>;
using Cert = Owned<X509, X509_free>;
struct CertsFree { void operator()(STACK_OF(X509)* p) const { sk_X509_pop_free(p, X509_free); } };
struct CrlsFree { void operator()(STACK_OF(X509_CRL)* p) const { sk_X509_CRL_pop_free(p, X509_CRL_free); } };
using Certs = std::unique_ptr<STACK_OF(X509), CertsFree>;
using Crls = std::unique_ptr<STACK_OF(X509_CRL), CrlsFree>;
void text(char* output, size_t size, const char* value) { std::strncpy(output, value, size-1); output[size-1]=0; }
CertificateBytes encode(X509* cert) {
    int n=i2d_X509(cert,nullptr); if(n<=0) return {};
    CertificateBytes bytes(n); auto* out=bytes.data(); i2d_X509(cert,&out); return bytes;
}
Cert decode(const CertificateBytes& bytes) {
    const auto* p=bytes.data(); Cert cert(d2i_X509(nullptr,&p,long(bytes.size())),X509_free);
    if(p!=bytes.data()+bytes.size()) cert.reset(); return cert;
}
CIE_TEMPORAL_VALIDATION empty() {
    CIE_TEMPORAL_VALIDATION r{}; r.size=sizeof(r); r.timestampStatus=CIE_TS_ABSENT;
    r.tsaRevocationStatus=r.signerRevocationStatus=REVOCATION_STATUS_UNKNOWN;
    text(r.timestampReason,sizeof(r.timestampReason),"signature_timestamp_absent");
    text(r.historicalReason,sizeof(r.historicalReason),"trusted_time_unavailable"); return r;
}
bool epoch(const ASN1_TIME* value, std::time_t& result) {
    if(!value || !ASN1_TIME_check(value)) return false;
    Owned<ASN1_TIME,ASN1_TIME_free> zero(ASN1_TIME_set(nullptr,0),ASN1_TIME_free);
    int days=0,seconds=0;
    if(!zero || !ASN1_TIME_diff(&days,&seconds,zero.get(),value)) return false;
    int64_t n=int64_t(days)*86400+seconds;
    if(n<0 || n>int64_t(std::numeric_limits<std::time_t>::max())) return false;
    result=std::time_t(n); return true;
}
bool strong(const EVP_MD* md) {
    if(!md) return false;
    int n=EVP_MD_get_type(md);
    return n==NID_sha256 || n==NID_sha384 || n==NID_sha512 ||
        n==NID_sha3_256 || n==NID_sha3_384 || n==NID_sha3_512;
}
bool strongSignature(X509_ALGOR* algorithm) {
    if(!algorithm) return false;
    int digestNid=0,keyNid=0;
    // PSS requires parameter validation beyond this deliberately narrow policy.
    return OBJ_find_sigid_algs(OBJ_obj2nid(algorithm->algorithm),&digestNid,&keyNid)==1 &&
        strong(EVP_get_digestbynid(digestNid));
}
// Require an authenticated full CRL covering the entire timestamp uncertainty
// interval. Revoked/suspended entries are never turned into historical GOOD,
// including a revocation after the timestamp (compromise/invalidity may predate it).
int archivedStatus(X509* target,X509* issuer,const std::vector<CertificateBytes>& crls,
    std::time_t lower,std::time_t upper) {
    bool good=false,unknown=false;
    for(const auto& bytes:crls) {
        const auto* p=bytes.data();
        Owned<X509_CRL,X509_CRL_free> crl(d2i_X509_CRL(nullptr,&p,long(bytes.size())),X509_CRL_free);
        if(!crl || p!=bytes.data()+bytes.size() || X509_NAME_cmp(X509_CRL_get_issuer(crl.get()),X509_get_subject_name(issuer))) continue;
        const X509_ALGOR* alg=nullptr; X509_CRL_get0_signature(crl.get(),nullptr,&alg);
        if(!strongSignature(const_cast<X509_ALGOR*>(alg))) continue;
        std::time_t from=0,until=0;
        if(!epoch(X509_CRL_get0_lastUpdate(crl.get()),from) || !epoch(X509_CRL_get0_nextUpdate(crl.get()),until) ||
            from>lower || until<upper || from>=until) continue;
        X509_REVOKED* entry=nullptr;
        if(X509_CRL_get0_by_cert(crl.get(),&entry,target)==1) {
            std::time_t revoked=0;
            if(!epoch(X509_REVOKED_get0_revocationDate(entry),revoked) || revoked>from) { unknown=true; continue; }
            bool unsupported=false;
            for(int e=0;e<X509_REVOKED_get_ext_count(entry);++e)
                unsupported=unsupported || X509_EXTENSION_get_critical(X509_REVOKED_get_ext(entry,e));
            if(unsupported) { unknown=true; continue; }
        }
        REVOCATION_INFO detail{};
        int status=verifyCrlResponse(bytes,target,issuer,&detail,lower);
        if(status==REVOCATION_STATUS_REVOKED || status==REVOCATION_STATUS_SUSPENDED) return status;
        if(status==REVOCATION_STATUS_GOOD) good=true; else unknown=true;
    }
    return good && !unknown ? REVOCATION_STATUS_GOOD : REVOCATION_STATUS_UNKNOWN;
}
struct HistoricalPath { uint32_t status=CIE_TRUST_UNKNOWN; int revocation=REVOCATION_STATUS_UNKNOWN; };
HistoricalPath historicalPath(const CertificateBytes& target,const std::vector<CertificateBytes>& candidates,
    const std::vector<CertificateBytes>& crls,std::time_t lower,std::time_t upper,
    const HttpOptions& network,const TemporalOptions& options) {
    auto policy=options.trust; policy.now=lower; policy.checkRevocation=false;
    auto first=validateCertificate(target,candidates,network,policy);
    if(first.trust.status!=CIE_TRUST_TRUSTED) return {first.trust.status,REVOCATION_STATUS_UNKNOWN};
    policy.now=upper;
    auto last=validateCertificate(target,candidates,network,policy);
    if(last.trust.status!=CIE_TRUST_TRUSTED) return {last.trust.status,REVOCATION_STATUS_UNKNOWN};
    // validateCertificate returns the actual approved path, not arbitrary CMS order.
    const auto& chain=first.chain;
    if(chain.size()<2 || chain!=last.chain) return {};
    int status=REVOCATION_STATUS_GOOD;
    for(size_t i=0;i+1<chain.size();++i) {
        auto cert=decode(chain[i]); auto issuer=decode(chain[i+1]);
        int n=cert && issuer ? archivedStatus(cert.get(),issuer.get(),crls,lower,upper) : REVOCATION_STATUS_UNKNOWN;
        if(n==REVOCATION_STATUS_REVOKED || n==REVOCATION_STATUS_SUSPENDED) return {CIE_TRUST_TRUSTED,n};
        if(n!=REVOCATION_STATUS_GOOD) status=REVOCATION_STATUS_UNKNOWN;
    }
    return {CIE_TRUST_TRUSTED,status};
}
std::vector<CertificateBytes> certificates(STACK_OF(X509)* stack) {
    std::vector<CertificateBytes> r;
    for(int i=0;i<sk_X509_num(stack) && i<64;++i) r.push_back(encode(sk_X509_value(stack,i)));
    return r;
}
void appendCrls(std::vector<CertificateBytes>& out,STACK_OF(X509_CRL)* stack) {
    size_t total=0; for(const auto& b:out) total+=b.size();
    for(int i=0;i<sk_X509_CRL_num(stack) && out.size()<64;++i) {
        auto* crl=sk_X509_CRL_value(stack,i); int n=i2d_X509_CRL(crl,nullptr);
        if(n<=0 || size_t(n)>64*1024*1024-total) break;
        CertificateBytes b(n); auto* p=b.data(); i2d_X509_CRL(crl,&p); total+=n; out.push_back(std::move(b));
    }
}
bool interval(TS_TST_INFO* info,std::time_t& when,long& uncertainty) {
    if(!epoch(TS_TST_INFO_get_time(info),when)) return false;
    // Missing accuracy is unspecified by RFC3161. Do not invent a precision.
    auto* accuracy=TS_TST_INFO_get_accuracy(info); if(!accuracy) return false;
    auto* sec=TS_ACCURACY_get_seconds(accuracy); auto* ms=TS_ACCURACY_get_millis(accuracy); auto* us=TS_ACCURACY_get_micros(accuracy);
    long seconds=sec ? ASN1_INTEGER_get(sec) : 0;
    long millis=ms ? ASN1_INTEGER_get(ms) : 0,micros=us ? ASN1_INTEGER_get(us) : 0;
    if(seconds<0 || seconds>86400 || (ms && (millis<1 || millis>999)) || (us && (micros<1 || micros>999))) return false;
    // Round fractions upward, plus one second for subsecond genTime truncation.
    uncertainty=seconds+(millis || micros ? 1 : 0)+1; return true;
}
}
CIE_TEMPORAL_VALIDATION validateTimestamp(const CertificateBytes& bytes,const CertificateBytes& data,
    const std::vector<CertificateBytes>& suppliedCrls,const HttpOptions& supplied,const TemporalOptions& options) {
    auto r=empty(); r.timestampStatus=CIE_TS_INVALID; r.timestampCount=1;
    text(r.timestampReason,sizeof(r.timestampReason),"timestamp_malformed");
    if(bytes.empty() || bytes.size()>4*1024*1024 || !initializeOpenSsl()) return r;
    const auto* p=bytes.data();
    Owned<PKCS7,PKCS7_free> token(d2i_PKCS7(nullptr,&p,long(bytes.size())),PKCS7_free);
    if(!token || p!=bytes.data()+bytes.size() || !PKCS7_type_is_signed(token.get()) ||
        sk_PKCS7_SIGNER_INFO_num(PKCS7_get_signer_info(token.get()))!=1) return r;
    Owned<TS_TST_INFO,TS_TST_INFO_free> info(PKCS7_to_TS_TST_INFO(token.get()),TS_TST_INFO_free);
    if(!info) return r;
    if(TS_TST_INFO_get_version(info.get())!=1) {
        r.timestampStatus=CIE_TS_INDETERMINATE;
        text(r.timestampReason,sizeof(r.timestampReason),"timestamp_version_unsupported"); return r;
    }
    // RFC 3161 permits optional TSTInfo extensions. Their signed bytes remain
    // covered by TS_RESP_verify_token below; noncritical metadata does not
    // supply trust, revocation evidence or a different timestamp meaning.
    // No critical extension semantics are implemented by this verifier.
    int extensionCount=TS_TST_INFO_get_ext_count(info.get());
    if(extensionCount>64) {
        r.timestampStatus=CIE_TS_INDETERMINATE;
        text(r.timestampReason,sizeof(r.timestampReason),"timestamp_extension_limit"); return r;
    }
    bool unsupportedCritical=false;
    for(int i=0;i<extensionCount;++i) {
        auto* extension=TS_TST_INFO_get_ext(info.get(),i);
        if(!extension || !X509_EXTENSION_get_object(extension) || !X509_EXTENSION_get_data(extension)) return r;
        for(int j=0;j<i;++j) {
            if(OBJ_cmp(X509_EXTENSION_get_object(extension),
                X509_EXTENSION_get_object(TS_TST_INFO_get_ext(info.get(),j)))==0) {
                text(r.timestampReason,sizeof(r.timestampReason),"timestamp_duplicate_extension"); return r;
            }
        }
        unsupportedCritical=unsupportedCritical || X509_EXTENSION_get_critical(extension);
    }
    if(unsupportedCritical) {
        r.timestampStatus=CIE_TS_INDETERMINATE;
        text(r.timestampReason,sizeof(r.timestampReason),"timestamp_critical_extension_unsupported"); return r;
    }
    auto* imprint=TS_TST_INFO_get_msg_imprint(info.get()); if(!imprint) return r;
    auto* algorithm=TS_MSG_IMPRINT_get_algo(imprint);
    const EVP_MD* md=algorithm ? EVP_get_digestbyobj(algorithm->algorithm) : nullptr;
    if(!strong(md)) {
        r.timestampStatus=CIE_TS_INDETERMINATE;
        text(r.timestampReason,sizeof(r.timestampReason),"timestamp_algorithm_unsupported"); return r;
    }
    auto* signerInfo=sk_PKCS7_SIGNER_INFO_value(PKCS7_get_signer_info(token.get()),0);
    if(!strongSignature(signerInfo->digest_enc_alg) || !strong(EVP_get_digestbyobj(signerInfo->digest_alg->algorithm))) {
        // rsaEncryption is normal CMS: digest_alg supplies its hash.
        if(OBJ_obj2nid(signerInfo->digest_enc_alg->algorithm)!=NID_rsaEncryption ||
            !strong(EVP_get_digestbyobj(signerInfo->digest_alg->algorithm))) {
            r.timestampStatus=CIE_TS_INDETERMINATE;
            text(r.timestampReason,sizeof(r.timestampReason),"timestamp_signature_algorithm_unsupported"); return r;
        }
    }
    auto* expected=TS_MSG_IMPRINT_get_msg(imprint);
    unsigned char hash[EVP_MAX_MD_SIZE]; unsigned int length=0;
    if(!expected || EVP_Digest(data.data(),data.size(),hash,&length,md,nullptr)!=1 ||
        ASN1_STRING_length(expected)!=int(length) || CRYPTO_memcmp(hash,ASN1_STRING_get0_data(expected),length)) {
        text(r.timestampReason,sizeof(r.timestampReason),"timestamp_imprint_mismatch"); return r;
    }
    std::time_t when=0; if(!epoch(TS_TST_INFO_get_time(info.get()),when) || when>options.now+300) {
        text(r.timestampReason,sizeof(r.timestampReason),"timestamp_time_invalid_or_future"); return r;
    }
    auto* tsa=PKCS7_cert_from_signer_info(token.get(),signerInfo); if(!tsa) return r;
    auto candidates=certificates(token->d.sign->cert);
    HttpOptions network=supplied; if(!network.budget) network.budget=std::make_shared<HttpBudget>();
    auto policy=options.trust; policy.now=when; policy.checkRevocation=false;
    auto trust=validateCertificate(encode(tsa),candidates,network,policy);
    if(trust.trust.status!=CIE_TRUST_TRUSTED || trust.chain.size()<2) {
        r.timestampStatus=CIE_TS_INDETERMINATE; text(r.timestampReason,sizeof(r.timestampReason),"tsa_chain_not_trusted_at_timestamp"); return r;
    }
    Owned<X509_STORE,X509_STORE_free> store(X509_STORE_new(),X509_STORE_free);
    auto anchor=decode(trust.chain.back());
    if(!store || !anchor || X509_STORE_add_cert(store.get(),anchor.get())!=1) return r;
    auto* param=X509_STORE_get0_param(store.get()); X509_VERIFY_PARAM_set_time(param,when);
    X509_VERIFY_PARAM_set_auth_level(param,2); X509_VERIFY_PARAM_set_depth(param,8);
    Certs additional(sk_X509_new_null());
    for(const auto& b:trust.chain) { auto c=decode(b); if(c && sk_X509_push(additional.get(),c.get())) c.release(); }
    // OpenSSL TS verification checks the signature, critical exclusive TSA EKU,
    // ESS signingCertificate(v2) binding and optional TSTInfo TSA name.
    Owned<TS_VERIFY_CTX,TS_VERIFY_CTX_free> ctx(TS_VERIFY_CTX_new(),TS_VERIFY_CTX_free);
    if(!ctx || !TS_VERIFY_CTX_set_flags(ctx.get(),TS_VFY_SIGNATURE|TS_VFY_VERSION|TS_VFY_SIGNER) ||
        !TS_VERIFY_CTX_set0_store(ctx.get(),store.release()) || !TS_VERIFY_CTX_set0_certs(ctx.get(),additional.release()) ||
        TS_RESP_verify_token(ctx.get(),token.get())!=1) {
        text(r.timestampReason,sizeof(r.timestampReason),"timestamp_signature_ess_or_tsa_purpose_invalid"); ERR_clear_error(); return r;
    }
    r.timestampStatus=CIE_TS_VERIFIED; r.referenceTime=when;
    std::tm tm{}; ASN1_TIME_to_tm(TS_TST_INFO_get_time(info.get()),&tm);
    std::strftime(r.utcTime,sizeof(r.utcTime),"%Y-%m-%dT%H:%M:%SZ",&tm);
    OBJ_obj2txt(r.policy,sizeof(r.policy),TS_TST_INFO_get_policy_id(info.get()),1);
    text(r.timestampReason,sizeof(r.timestampReason),"imprint_signature_ess_and_tsa_chain_verified");
    long accuracy=0;
    if(!interval(info.get(),when,accuracy) || when<accuracy || when+accuracy>options.now+300) {
        text(r.historicalReason,sizeof(r.historicalReason),"timestamp_accuracy_missing_or_unsupported"); return r;
    }
    auto crls=suppliedCrls; appendCrls(crls,token->d.sign->crl);
    auto historical=historicalPath(encode(tsa),candidates,crls,when-accuracy,when+accuracy,network,options);
    r.tsaRevocationStatus=historical.revocation;
    // A compromised TSA key can backdate newly forged tokens. Without an
    // archive-timestamp renewal chain, require TSA trust/revocation TODAY too.
    auto current=historicalPath(encode(tsa),candidates,crls,options.now,options.now,network,options);
    if(current.status==CIE_TRUST_TRUSTED && current.revocation!=REVOCATION_STATUS_GOOD) {
        auto currentPolicy=options.trust; currentPolicy.now=options.now; currentPolicy.checkRevocation=true;
        auto online=validateCertificate(encode(tsa),candidates,network,currentPolicy);
        current.revocation=online.trust.revocationStatus;
    }
    if(current.status!=CIE_TRUST_TRUSTED || current.revocation!=REVOCATION_STATUS_GOOD) {
        text(r.historicalReason,sizeof(r.historicalReason),"tsa_current_status_missing_requires_archive_renewal_proof"); return r;
    }
    text(r.historicalReason,sizeof(r.historicalReason),historical.status!=CIE_TRUST_TRUSTED ?
        "tsa_validity_does_not_cover_timestamp_interval" : historical.revocation!=REVOCATION_STATUS_GOOD ?
        "tsa_historical_revocation_evidence_missing_or_adverse" : "signer_historical_validation_pending");
    return r;
}
CIE_TEMPORAL_VALIDATION validateCmsTemporal(const CertificateBytes& bytes,const CertificateBytes& signer,
    const CertificateBytes& signature,bool signatureValid,const HttpOptions& network,const TemporalOptions& options) {
    auto r=empty();
    const auto* p=bytes.data();
    Owned<CMS_ContentInfo,CMS_ContentInfo_free> cms(d2i_CMS_ContentInfo(nullptr,&p,long(bytes.size())),CMS_ContentInfo_free);
    if(!cms || p!=bytes.data()+bytes.size()) {
        r.timestampStatus=CIE_TS_INDETERMINATE; text(r.timestampReason,sizeof(r.timestampReason),"cms_timestamp_unreadable"); return r;
    }
    auto cert=decode(signer); auto* signers=CMS_get0_SignerInfos(cms.get()); CMS_SignerInfo* si=nullptr;
    for(int i=0;cert && i<sk_CMS_SignerInfo_num(signers) && i<64;++i) {
        auto* candidate=sk_CMS_SignerInfo_value(signers,i); auto* value=CMS_SignerInfo_get0_signature(candidate);
        if(CMS_SignerInfo_cert_cmp(candidate,cert.get())==0 && value && signature.size()==size_t(ASN1_STRING_length(value)) &&
            !CRYPTO_memcmp(signature.data(),ASN1_STRING_get0_data(value),signature.size())) { si=candidate; break; }
    }
    if(!si) { r.timestampStatus=CIE_TS_INDETERMINATE; text(r.timestampReason,sizeof(r.timestampReason),"cms_signer_not_identified"); return r; }
    int location=CMS_unsigned_get_attr_by_NID(si,NID_id_smime_aa_timeStampToken,-1);
    if(location<0) return r;
    auto* attribute=CMS_unsigned_get_attr(si,location);
    r.timestampStatus=CIE_TS_INVALID;
    if(CMS_unsigned_get_attr_by_NID(si,NID_id_smime_aa_timeStampToken,location)>=0 || X509_ATTRIBUTE_count(attribute)!=1) {
        text(r.timestampReason,sizeof(r.timestampReason),"multiple_signature_timestamps_unsupported"); return r;
    }
    auto* value=X509_ATTRIBUTE_get0_type(attribute,0);
    if(!value || value->type!=V_ASN1_SEQUENCE) { text(r.timestampReason,sizeof(r.timestampReason),"timestamp_attribute_malformed"); return r; }
    Crls embedded(CMS_get1_crls(cms.get())); std::vector<CertificateBytes> crls; appendCrls(crls,embedded.get());
    CertificateBytes token(ASN1_STRING_get0_data(value->value.sequence),ASN1_STRING_get0_data(value->value.sequence)+ASN1_STRING_length(value->value.sequence));
    r=validateTimestamp(token,signature,crls,network,options);
    if(!signatureValid) { r.historicalStatus=CIE_HISTORY_INVALID; text(r.historicalReason,sizeof(r.historicalReason),"document_signature_invalid"); return r; }
    if(r.timestampStatus!=CIE_TS_VERIFIED) return r;
    // Only the success reason below proves all TSA prerequisites, including
    // current TSA status. A historical GOOD alone cannot authorize backdating.
    if(std::strcmp(r.historicalReason,"signer_historical_validation_pending")) return r;
    X509_ALGOR* digestAlgorithm=nullptr;
    CMS_SignerInfo_get0_algs(si,nullptr,nullptr,&digestAlgorithm,nullptr);
    if(!digestAlgorithm || !strong(EVP_get_digestbyobj(digestAlgorithm->algorithm))) {
        text(r.historicalReason,sizeof(r.historicalReason),"document_signature_algorithm_unsupported_for_history"); return r;
    }
    // Read accuracy from the already authenticated token. This is not signingTime.
    const auto* cursor=token.data(); Owned<PKCS7,PKCS7_free> parsed(d2i_PKCS7(nullptr,&cursor,long(token.size())),PKCS7_free);
    Owned<TS_TST_INFO,TS_TST_INFO_free> info(parsed ? PKCS7_to_TS_TST_INFO(parsed.get()) : nullptr,TS_TST_INFO_free);
    std::time_t when=0; long accuracy=0;
    if(!info || !interval(info.get(),when,accuracy)) return r;
    Certs candidates(CMS_get1_certs(cms.get())); auto pool=certificates(candidates.get());
    auto path=historicalPath(signer,pool,crls,when-accuracy,when+accuracy,network,options);
    r.signerRevocationStatus=path.revocation;
    if(path.status==CIE_TRUST_INVALID || path.revocation==REVOCATION_STATUS_REVOKED || path.revocation==REVOCATION_STATUS_SUSPENDED) {
        r.historicalStatus=CIE_HISTORY_INVALID; text(r.historicalReason,sizeof(r.historicalReason),"signer_invalid_or_revoked_at_reference_time");
    } else if(r.tsaRevocationStatus==REVOCATION_STATUS_GOOD && path.status==CIE_TRUST_TRUSTED && path.revocation==REVOCATION_STATUS_GOOD) {
        r.historicalStatus=CIE_HISTORY_VALID; text(r.historicalReason,sizeof(r.historicalReason),"trusted_timestamp_and_embedded_complete_crls");
    } else if(r.tsaRevocationStatus==REVOCATION_STATUS_GOOD) {
        text(r.historicalReason,sizeof(r.historicalReason),"signer_historical_chain_or_revocation_evidence_missing");
    }
    return r;
}
}
