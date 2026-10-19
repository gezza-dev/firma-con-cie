// SPDX-License-Identifier: BSD-3-Clause
#include "CertificateTrust.h"
#include "Digest.h"
#include "TrustMaterial.h"
#include <openssl/pem.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>
#include <memory>
#include <cstring>
#include <algorithm>

namespace cie {
namespace {
using Cert = std::unique_ptr<X509, decltype(&X509_free)>;
Cert decode(const CertificateBytes& bytes) {
    const auto* cursor = bytes.data();
    Cert result(d2i_X509(nullptr, &cursor, long(bytes.size())), X509_free);
    if (cursor != bytes.data() + bytes.size()) result.reset();
    return result;
}
CertificateBytes encode(X509* cert) {
    int length = i2d_X509(cert, nullptr);
    if (length <= 0) return {};
    CertificateBytes bytes(length); auto* cursor = bytes.data();
    return i2d_X509(cert, &cursor) == length ? bytes : CertificateBytes{};
}
std::vector<CertificateBytes> pemCertificates(const char* pem) {
    std::vector<CertificateBytes> result;
    std::unique_ptr<BIO, decltype(&BIO_free_all)> bio(BIO_new_mem_buf(pem, -1), BIO_free_all);
    while (bio) {
        Cert cert(PEM_read_bio_X509(bio.get(), nullptr, nullptr, nullptr), X509_free);
        if (!cert) break;
        result.push_back(encode(cert.get()));
    }
    ERR_clear_error();
    return result;
}
struct StackFree { void operator()(STACK_OF(X509)* p) const { sk_X509_pop_free(p, X509_free); } };
using Stack = std::unique_ptr<STACK_OF(X509), StackFree>;
struct Path {
    int error = X509_V_ERR_UNSPECIFIED;
    std::vector<CertificateBytes> certificates;
};
Path build(X509* target, const std::vector<CertificateBytes>& candidates,
           const std::vector<CertificateBytes>& anchors, std::time_t now) {
    Path result;
    std::unique_ptr<X509_STORE, decltype(&X509_STORE_free)> store(X509_STORE_new(), X509_STORE_free);
    Stack untrusted(sk_X509_new_null());
    std::unique_ptr<X509_STORE_CTX, decltype(&X509_STORE_CTX_free)> context(X509_STORE_CTX_new(), X509_STORE_CTX_free);
    if (!store || !untrusted || !context) return result;
    for (const auto& bytes : anchors) {
        auto cert = decode(bytes);
        if (cert && X509_check_ca(cert.get()) > 0) {
            if (X509_STORE_add_cert(store.get(), cert.get()) != 1) ERR_clear_error();
        }
    }
    for (const auto& bytes : candidates) {
        auto cert = decode(bytes);
        if (cert && sk_X509_num(untrusted.get()) < 128) {
            if (!sk_X509_push(untrusted.get(), cert.get())) return result;
            cert.release();
        }
    }
    if (X509_STORE_CTX_init(context.get(), store.get(), target, untrusted.get()) != 1) return result;
    auto* param = X509_STORE_CTX_get0_param(context.get());
    X509_VERIFY_PARAM_set_depth(param, 8);
    X509_VERIFY_PARAM_set_auth_level(param, 2);
    X509_VERIFY_PARAM_set_time(param, now);
    X509_VERIFY_PARAM_set_flags(param, X509_V_FLAG_TRUSTED_FIRST | X509_V_FLAG_CHECK_SS_SIGNATURE);
    int valid = X509_verify_cert(context.get());
    result.error = valid == 1 ? X509_V_OK : X509_STORE_CTX_get_error(context.get());
    Stack chain(X509_STORE_CTX_get1_chain(context.get()));
    for (int i = 0; chain && i < sk_X509_num(chain.get()); ++i)
        result.certificates.push_back(encode(sk_X509_value(chain.get(), i)));
    return result;
}
bool missingIssuer(int error) {
    return error == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY ||
        error == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT || error == X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE;
}
void copy(char* dest, size_t size, const char* text) {
    std::strncpy(dest, text, size - 1); dest[size - 1] = 0;
}
const char* failureReason(int error) {
    switch (error) {
        case X509_V_ERR_CERT_HAS_EXPIRED: return "certificate_expired";
        case X509_V_ERR_CERT_NOT_YET_VALID: return "certificate_not_yet_valid";
        case X509_V_ERR_CERT_SIGNATURE_FAILURE: return "certificate_signature_invalid";
        case X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT:
        case X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN: return "untrusted_root";
        case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY:
        case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT:
        case X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE: return "issuer_missing";
        default: return "certificate_constraints_invalid";
    }
}
}
std::vector<CertificateBytes> cieIssuerCertificates() {
    static const auto certs = [] { auto all = pemCertificates(cieIssuersPem);
        auto roots = pemCertificates(cieRootPem); all.insert(all.end(), roots.begin(), roots.end()); return all; }();
    return certs;
}
CertificateValidation validateCertificate(const CertificateBytes& bytes,
    const std::vector<CertificateBytes>& candidates, const HttpOptions& supplied, const TrustOptions& options) {
    CertificateValidation result;
    auto& info = result.trust; info.size = sizeof(info); info.status = CIE_TRUST_UNKNOWN;
    info.revocationStatus = result.leaf.nRevocationStatus = REVOCATION_STATUS_UNKNOWN;
    copy(info.reason, sizeof(info.reason), "certificate_unreadable");
    copy(info.revocationReason, sizeof(info.revocationReason), "chain_not_trusted");
    if (!initializeOpenSsl()) return result;
    auto target = decode(bytes);
    if (!target) return result;
    HttpOptions network = supplied;
    network.allowNetwork = supplied.allowNetwork && options.allowNetwork;
    if (!network.budget) network.budget = std::make_shared<HttpBudget>();
    auto pool = candidates;
    if (pool.size() > 64) pool.resize(64);
    auto anchors = options.anchors;
    auto cieRoots = options.useCieAuthorities ? pemCertificates(cieRootPem) : std::vector<CertificateBytes>{};
    auto difesaRoots = options.useDifesaAuthorities ? pemCertificates(difesaRootsPem) : std::vector<CertificateBytes>{};
    anchors.insert(anchors.end(), difesaRoots.begin(), difesaRoots.end());
    if (options.useCieAuthorities) {
        anchors.insert(anchors.end(), cieRoots.begin(), cieRoots.end());
        auto issuers = cieIssuerCertificates(); pool.insert(pool.end(), issuers.begin(), issuers.end());
    }
    auto path = build(target.get(), pool, anchors, options.now);
    const char* source = "explicit_policy";
    for (int attempt = 0; attempt < 5 && path.error != X509_V_OK; ++attempt) {
        if (options.useSystemTrust) {
            auto system = systemTrustedChain(bytes, pool, options.now);
            if (!system.empty()) {
                auto checked = build(target.get(), system, {system.back()}, options.now);
                if (checked.error == X509_V_OK) { path = std::move(checked); source = "system"; break; }
            }
        }
        if (!network.allowNetwork || !missingIssuer(path.error) || path.certificates.empty()) break;
        auto issuer = findCertificateIssuer(path.certificates.back(), pool, network);
        if (issuer.empty() || std::find(pool.begin(), pool.end(), issuer) != pool.end()) break;
        pool.push_back(std::move(issuer));
        path = build(target.get(), pool, anchors, options.now);
    }
    const auto usage = X509_get_key_usage(target.get());
    if (path.error == X509_V_OK && usage != UINT32_MAX && !(usage & (KU_DIGITAL_SIGNATURE | KU_NON_REPUDIATION)))
        path.error = X509_V_ERR_INVALID_PURPOSE;
    info.error = path.error; info.chainLength = uint32_t(path.certificates.size());
    if (path.error != X509_V_OK) {
        info.status = missingIssuer(path.error) ? CIE_TRUST_UNKNOWN :
            (path.error == X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT || path.error == X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN)
                ? CIE_TRUST_UNTRUSTED : CIE_TRUST_INVALID;
        copy(info.reason, sizeof(info.reason), failureReason(path.error));
        return result;
    }
    info.status = CIE_TRUST_TRUSTED;
    if(std::strcmp(source,"system") && !path.certificates.empty()) {
        const auto& root=path.certificates.back();
        if(std::find(cieRoots.begin(),cieRoots.end(),root)!=cieRoots.end()) source="cie_ministry";
        else if(std::find(difesaRoots.begin(),difesaRoots.end(),root)!=difesaRoots.end()) source="difesa_ministry";
    }
    result.chain = path.certificates;
    copy(info.trustSource, sizeof(info.trustSource), source);
    copy(info.reason, sizeof(info.reason), "trusted_current_chain");
    if (!options.checkRevocation) {
        copy(info.revocationReason, sizeof(info.revocationReason), "not_requested"); return result;
    }
    int aggregate = REVOCATION_STATUS_GOOD;
    // A root is a policy anchor: its revocation is handled by trust-store updates.
    for (size_t i = 0; i + 1 < path.certificates.size(); ++i) {
        REVOCATION_INFO revocation{}; revocation.nRevocationStatus = REVOCATION_STATUS_UNKNOWN;
        int status = checkRevocation(path.certificates[i], {path.certificates[i + 1]}, network, &revocation, options.now);
        if (i == 0) { result.leaf = revocation; info.revocationType = revocation.nType; }
        if (status == REVOCATION_STATUS_REVOKED) aggregate = status;
        else if (status == REVOCATION_STATUS_SUSPENDED && aggregate != REVOCATION_STATUS_REVOKED) aggregate = status;
        else if (status != REVOCATION_STATUS_GOOD && aggregate == REVOCATION_STATUS_GOOD) aggregate = REVOCATION_STATUS_UNKNOWN;
    }
    if (path.certificates.size() < 2) aggregate = REVOCATION_STATUS_UNKNOWN;
    info.revocationStatus = aggregate;
    copy(info.revocationReason, sizeof(info.revocationReason), aggregate == REVOCATION_STATUS_GOOD ? "all_non_root_certificates_good" :
        aggregate == REVOCATION_STATUS_REVOKED ? "certificate_revoked" : aggregate == REVOCATION_STATUS_SUSPENDED ? "certificate_suspended" :
        network.allowNetwork ? "revocation_unavailable_or_invalid" : "network_disabled");
    return result;
}
}
