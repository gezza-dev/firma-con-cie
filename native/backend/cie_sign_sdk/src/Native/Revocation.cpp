// SPDX-License-Identifier: BSD-3-Clause
#include "Revocation.h"
#include "Digest.h"
#include "CertificateTrust.h"
#include <openssl/ocsp.h>
#include <openssl/pem.h>
#include <openssl/x509v3.h>
#include <algorithm>
#include <cstring>
#include <memory>

namespace cie {
namespace {
template<class T, void(*Free)(T*)> using Owned = std::unique_ptr<T, decltype(Free)>;
using Certificate = Owned<X509, X509_free>;
Certificate decode(const CertificateBytes& data)
{
    const unsigned char* p = data.data();
    Certificate cert(d2i_X509(nullptr, &p, long(data.size())), X509_free);
    if (cert && p == data.data() + data.size()) return cert;
    Owned<BIO, BIO_free_all> bio(BIO_new_mem_buf(data.data(), int(data.size())), BIO_free_all);
    return Certificate(bio ? PEM_read_bio_X509(bio.get(), nullptr, nullptr, nullptr) : nullptr, X509_free);
}
bool issuerOf(X509* issuer, X509* target)
{
    if (!issuer || X509_check_ca(issuer) <= 0 || X509_check_issued(issuer, target) != X509_V_OK) return false;
    Owned<EVP_PKEY, EVP_PKEY_free> key(X509_get_pubkey(issuer), EVP_PKEY_free);
    return key && X509_verify(target, key.get()) == 1;
}
Certificate fromContainer(const CertificateBytes& bytes, X509* target)
{
    auto single = decode(bytes);
    if (single && issuerOf(single.get(), target)) return single;
    const unsigned char* cursor = bytes.data();
    Owned<PKCS7, PKCS7_free> container(d2i_PKCS7(nullptr, &cursor, long(bytes.size())), PKCS7_free);
    if (container && cursor == bytes.data() + bytes.size() && PKCS7_type_is_signed(container.get())) {
        STACK_OF(X509)* certs = container->d.sign->cert;
        for (int i = 0; i < sk_X509_num(certs); ++i)
            if (issuerOf(sk_X509_value(certs, i), target)) return Certificate(X509_dup(sk_X509_value(certs, i)), X509_free);
    }
    return Certificate(nullptr, X509_free);
}
std::vector<std::string> issuerUrls(X509* cert)
{
    std::vector<std::string> urls;
    Owned<AUTHORITY_INFO_ACCESS, AUTHORITY_INFO_ACCESS_free> access(
        static_cast<AUTHORITY_INFO_ACCESS*>(X509_get_ext_d2i(cert, NID_info_access, nullptr, nullptr)), AUTHORITY_INFO_ACCESS_free);
    for (int i = 0; access && i < sk_ACCESS_DESCRIPTION_num(access.get()) && urls.size() < 4; ++i) {
        auto* item = sk_ACCESS_DESCRIPTION_value(access.get(), i);
        if (OBJ_obj2nid(item->method) != NID_ad_ca_issuers || item->location->type != GEN_URI) continue;
        auto* uri = item->location->d.uniformResourceIdentifier;
        std::string url(reinterpret_cast<const char*>(ASN1_STRING_get0_data(uri)), ASN1_STRING_length(uri));
        if (url.find('\0') == std::string::npos) urls.push_back(url);
    }
    return urls;
}
Certificate findIssuer(X509* target, const std::vector<CertificateBytes>& candidates, const HttpOptions& network)
{
    for (const auto& bytes : candidates) {
        auto candidate = fromContainer(bytes, target);
        if (candidate) return candidate;
    }
    if (issuerOf(target, target)) return Certificate(X509_dup(target), X509_free);
    // AIA supplies untrusted candidates only: issuerOf verifies both the
    // issuer constraints and the signature of the original target certificate.
    for (const auto& url : issuerUrls(target)) {
        auto reply = httpRequest(url, {}, nullptr, network, 1024 * 1024);
        if (reply.error != CURLE_OK) continue;
        auto candidate = fromContainer(reply.body, target);
        if (candidate) return candidate;
    }
    return Certificate(nullptr, X509_free);
}
bool validWindow(const ASN1_TIME* from, const ASN1_TIME* until, std::time_t now, bool requireUntil)
{
    if (!from || !ASN1_TIME_check(from) || (requireUntil && !until) || (until && !ASN1_TIME_check(until))) return false;
    std::time_t future = now + 300, past = now - 300;
    if (X509_cmp_time(from, &future) != -1 || (until && X509_cmp_time(until, &past) != 1)) return false;
    if (until && ASN1_TIME_compare(from, until) >= 0) return false;
    // Responses without nextUpdate must be recent, not indefinitely replayable.
    std::time_t oldest = now - 86400;
    return until || X509_cmp_time(from, &oldest) == 1;
}
void copyTime(const ASN1_TIME* source, char* output, size_t capacity)
{
    std::tm tm{};
    if (source && ASN1_TIME_to_tm(source, &tm) == 1) std::strftime(output, capacity, "%y%m%d%H%M%SZ", &tm);
}
int ocspStatus(X509* target, X509* issuer, const HttpOptions& network, REVOCATION_INFO* info, std::time_t now)
{
    STACK_OF(OPENSSL_STRING)* urls = X509_get1_ocsp(target);
    if (!urls) return REVOCATION_STATUS_UNKNOWN;
    std::unique_ptr<STACK_OF(OPENSSL_STRING), decltype(&X509_email_free)> ownedUrls(urls, X509_email_free);
    Owned<OCSP_CERTID, OCSP_CERTID_free> id(OCSP_cert_to_id(EVP_sha1(), target, issuer), OCSP_CERTID_free);
    Owned<OCSP_REQUEST, OCSP_REQUEST_free> request(OCSP_REQUEST_new(), OCSP_REQUEST_free);
    if (!id || !request || !OCSP_request_add0_id(request.get(), OCSP_CERTID_dup(id.get())) ||
        OCSP_request_add1_nonce(request.get(), nullptr, -1) != 1) return REVOCATION_STATUS_UNKNOWN;
    int length = i2d_OCSP_REQUEST(request.get(), nullptr);
    if (length <= 0) return REVOCATION_STATUS_UNKNOWN;
    CertificateBytes body(size_t(length), 0); auto* destination = body.data();
    if (i2d_OCSP_REQUEST(request.get(), &destination) != length) return REVOCATION_STATUS_UNKNOWN;
    for (int i = 0; i < sk_OPENSSL_STRING_num(urls) && i < 4; ++i) {
        auto reply = httpRequest(sk_OPENSSL_STRING_value(urls, i), body, "application/ocsp-request", network, 1024 * 1024);
        if (reply.error != CURLE_OK || reply.body.empty()) continue;
        int result = verifyOcspResponse(reply.body, target, issuer, request.get(), info, now);
        if (result != REVOCATION_STATUS_UNKNOWN) return result;
    }
    return REVOCATION_STATUS_UNKNOWN;
}
bool retryableCrlDownload(const HttpResponse& response)
{
    if(response.error==CURLE_HTTP_RETURNED_ERROR)
        return response.status==408 || response.status==500 || response.status==502 ||
            response.status==503 || response.status==504;
    return response.error==CURLE_COULDNT_RESOLVE_HOST || response.error==CURLE_COULDNT_CONNECT ||
        response.error==CURLE_OPERATION_TIMEDOUT || response.error==CURLE_RECV_ERROR ||
        response.error==CURLE_SEND_ERROR || response.error==CURLE_GOT_NOTHING ||
        response.error==CURLE_PARTIAL_FILE || response.error==CURLE_SSL_CONNECT_ERROR;
}
int crlStatus(X509* target, X509* issuer, const HttpOptions& network, REVOCATION_INFO* info, std::time_t now)
{
    Owned<CRL_DIST_POINTS, CRL_DIST_POINTS_free> points(
        static_cast<CRL_DIST_POINTS*>(X509_get_ext_d2i(target, NID_crl_distribution_points, nullptr, nullptr)), CRL_DIST_POINTS_free);
    int requests = 0;
    for (int i = 0; points && i < sk_DIST_POINT_num(points.get()) && requests < 4; ++i) {
        auto* point = sk_DIST_POINT_value(points.get(), i);
        if (!point->distpoint || point->distpoint->type != 0 || point->CRLissuer || point->reasons) continue;
        auto* names = point->distpoint->name.fullname;
        for (int j = 0; j < sk_GENERAL_NAME_num(names) && requests < 4; ++j) {
            auto* name = sk_GENERAL_NAME_value(names, j);
            if (name->type != GEN_URI) continue;
            auto* uri = name->d.uniformResourceIdentifier;
            std::string url(reinterpret_cast<const char*>(ASN1_STRING_get0_data(uri)), ASN1_STRING_length(uri));
            if (url.find('\0') != std::string::npos) continue;
            // Complete CIE issuing-CA CRLs can exceed 32 MiB. Keep a finite
            // 64 MiB cap, with the shared request/time budget still enforced.
            for(int attempt=0;attempt<2 && requests<4;++attempt) {
                ++requests;
                auto reply = httpRequest(url, {}, nullptr, network, 64 * 1024 * 1024);
                if (reply.error == CURLE_OK && !reply.body.empty()) {
                    int result = verifyCrlResponse(reply.body, target, issuer, info, now);
                    if (result != REVOCATION_STATUS_UNKNOWN) return result;
                    // An unauthenticated/stale CRL is not a transport failure.
                    break;
                }
                // The same request/deadline budget covers the retry. Certificate
                // verification errors, size limits and permanent HTTP errors do
                // not trigger another request or reduce TLS validation.
                if(!retryableCrlDownload(reply)) break;
            }
        }
    }
    return REVOCATION_STATUS_UNKNOWN;
}
}
int verifyOcspResponse(const CertificateBytes& responseBytes, X509* target, X509* issuer,
    OCSP_REQUEST* request, REVOCATION_INFO* info, std::time_t now)
{
    if (!target || !issuer || !request || !issuerOf(issuer, target)) return REVOCATION_STATUS_UNKNOWN;
    Owned<OCSP_CERTID, OCSP_CERTID_free> id(OCSP_cert_to_id(EVP_sha1(), target, issuer), OCSP_CERTID_free);
    if (!id) return REVOCATION_STATUS_UNKNOWN;
    Owned<X509_STORE, X509_STORE_free> store(X509_STORE_new(), X509_STORE_free);
    // This anchor authorizes revocation for this target only; it does not
    // assert that the document's signer is trusted by macOS or an EU trust list.
    if (!store || X509_STORE_add_cert(store.get(), issuer) != 1 ||
        X509_STORE_set_flags(store.get(), X509_V_FLAG_PARTIAL_CHAIN | X509_V_FLAG_TRUSTED_FIRST) != 1)
        return REVOCATION_STATUS_UNKNOWN;
    X509_VERIFY_PARAM_set_time(X509_STORE_get0_param(store.get()), now);
    const unsigned char* cursor = responseBytes.data();
    Owned<OCSP_RESPONSE, OCSP_RESPONSE_free> response(d2i_OCSP_RESPONSE(nullptr, &cursor, long(responseBytes.size())), OCSP_RESPONSE_free);
    if (!response || cursor != responseBytes.data() + responseBytes.size() || OCSP_response_status(response.get()) != OCSP_RESPONSE_STATUS_SUCCESSFUL) return REVOCATION_STATUS_UNKNOWN;
    Owned<OCSP_BASICRESP, OCSP_BASICRESP_free> basic(OCSP_response_get1_basic(response.get()), OCSP_BASICRESP_free);
    // No OCSP_NOVERIFY / NOSIGS / NOCHECKS flags: verify signature, chain,
    // delegated-responder EKU and its authority for the requested issuer.
    if (!basic || OCSP_basic_verify(basic.get(), nullptr, store.get(), 0) != 1 ||
        OCSP_check_nonce(request, basic.get()) == 0) return REVOCATION_STATUS_UNKNOWN;
    int status = V_OCSP_CERTSTATUS_UNKNOWN, reason = 0;
    ASN1_GENERALIZEDTIME *revoked = nullptr, *from = nullptr, *until = nullptr;
    if (OCSP_resp_find_status(basic.get(), id.get(), &status, &reason, &revoked, &from, &until) != 1 ||
        !validWindow(from, until, now, false) ||
        !validWindow(OCSP_resp_get0_produced_at(basic.get()), nullptr, now, false)) return REVOCATION_STATUS_UNKNOWN;
    int result = REVOCATION_STATUS_UNKNOWN;
    if (status == V_OCSP_CERTSTATUS_GOOD) result = REVOCATION_STATUS_GOOD;
    else if (status == V_OCSP_CERTSTATUS_REVOKED) {
        std::time_t latest = now + 300;
        if (!revoked || X509_cmp_time(revoked, &latest) != -1) return REVOCATION_STATUS_UNKNOWN;
        result = reason == OCSP_REVOKED_STATUS_CERTIFICATEHOLD ? REVOCATION_STATUS_SUSPENDED : REVOCATION_STATUS_REVOKED;
    }
    if (info) {
        info->nType = TYPE_OCSP; info->nRevocationStatus = result;
        copyTime(from, info->szThisUpdate, sizeof(info->szThisUpdate));
        copyTime(revoked, info->szRevocationDate, sizeof(info->szRevocationDate));
    }
    return result;
}
int verifyCrlResponse(const CertificateBytes& responseBytes, X509* target, X509* issuer,
    REVOCATION_INFO* info, std::time_t now)
{
    if (!target || !issuer || !issuerOf(issuer, target)) return REVOCATION_STATUS_UNKNOWN;
    const uint32_t usage = X509_get_key_usage(issuer);
    if ((usage != UINT32_MAX && !(usage & KU_CRL_SIGN)) ||
        X509_cmp_time(X509_get0_notBefore(issuer), &now) != -1 ||
        X509_cmp_time(X509_get0_notAfter(issuer), &now) != 1) return REVOCATION_STATUS_UNKNOWN;
    const unsigned char* cursor = responseBytes.data();
    Owned<X509_CRL, X509_CRL_free> crl(d2i_X509_CRL(nullptr, &cursor, long(responseBytes.size())), X509_CRL_free);
    if (!crl || cursor != responseBytes.data() + responseBytes.size()) {
        Owned<BIO, BIO_free_all> bio(BIO_new_mem_buf(responseBytes.data(), int(responseBytes.size())), BIO_free_all);
        crl.reset(bio ? PEM_read_bio_X509_CRL(bio.get(), nullptr, nullptr, nullptr) : nullptr);
    }
    if (!crl || X509_NAME_cmp(X509_CRL_get_issuer(crl.get()), X509_get_subject_name(issuer)) != 0 ||
        X509_CRL_get_ext_by_NID(crl.get(), NID_delta_crl, -1) >= 0 ||
        X509_CRL_get_ext_by_NID(crl.get(), NID_issuing_distribution_point, -1) >= 0 ||
        !validWindow(X509_CRL_get0_lastUpdate(crl.get()), X509_CRL_get0_nextUpdate(crl.get()), now, true)) return REVOCATION_STATUS_UNKNOWN;
    bool unsupported = false;
    for (int e = 0; e < X509_CRL_get_ext_count(crl.get()); ++e) {
        auto* extension = X509_CRL_get_ext(crl.get(), e);
        if (X509_EXTENSION_get_critical(extension)) unsupported = true;
    }
    if (unsupported) return REVOCATION_STATUS_UNKNOWN;
    Owned<EVP_PKEY, EVP_PKEY_free> key(X509_get_pubkey(issuer), EVP_PKEY_free);
    if (!key || X509_CRL_verify(crl.get(), key.get()) != 1) return REVOCATION_STATUS_UNKNOWN;
    X509_REVOKED* entry = nullptr;
    int result = REVOCATION_STATUS_GOOD;
    if (X509_CRL_get0_by_cert(crl.get(), &entry, target) == 1) {
        result = REVOCATION_STATUS_REVOKED;
        Owned<ASN1_ENUMERATED, ASN1_ENUMERATED_free> reason(
            static_cast<ASN1_ENUMERATED*>(X509_REVOKED_get_ext_d2i(entry, NID_crl_reason, nullptr, nullptr)), ASN1_ENUMERATED_free);
        if (reason && ASN1_ENUMERATED_get(reason.get()) == CRL_REASON_CERTIFICATE_HOLD) result = REVOCATION_STATUS_SUSPENDED;
    }
    if (info) {
        info->nType = TYPE_CRL; info->nRevocationStatus = result;
        copyTime(X509_CRL_get0_lastUpdate(crl.get()), info->szThisUpdate, sizeof(info->szThisUpdate));
        if (entry) copyTime(X509_REVOKED_get0_revocationDate(entry), info->szRevocationDate, sizeof(info->szRevocationDate));
    }
    return result;
}

int checkRevocation(const CertificateBytes& bytes, const std::vector<CertificateBytes>& candidates,
                    const HttpOptions& network, REVOCATION_INFO* info, std::time_t now)
{
    if (info) { *info = {}; info->nRevocationStatus = REVOCATION_STATUS_UNKNOWN; }
    try {
        if (!initializeOpenSsl()) return REVOCATION_STATUS_UNKNOWN;
        auto target = decode(bytes);
        if (!target) return REVOCATION_STATUS_UNKNOWN;
        auto issuers = candidates;
        auto official = cieIssuerCertificates();
        issuers.insert(issuers.end(), official.begin(), official.end());
        auto issuer = findIssuer(target.get(), issuers, network);
        if (!issuer) return REVOCATION_STATUS_UNKNOWN;
        int status = ocspStatus(target.get(), issuer.get(), network, info, now);
        if (status != REVOCATION_STATUS_UNKNOWN) return status;
        return crlStatus(target.get(), issuer.get(), network, info, now);
    } catch (...) { return REVOCATION_STATUS_UNKNOWN; }
}
CertificateBytes findCertificateIssuer(const CertificateBytes& bytes,
    const std::vector<CertificateBytes>& candidates, const HttpOptions& network)
{
    auto target = decode(bytes);
    auto issuer = target ? findIssuer(target.get(), candidates, network) : Certificate(nullptr, X509_free);
    if (!issuer) return {};
    int length = i2d_X509(issuer.get(), nullptr);
    if (length <= 0) return {};
    CertificateBytes result(length); auto* cursor = result.data();
    if (i2d_X509(issuer.get(), &cursor) != length) return {};
    return result;
}
}
