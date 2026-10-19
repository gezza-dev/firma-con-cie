// SPDX-License-Identifier: BSD-3-Clause
#include "CertificateTrust.h"
#ifdef __APPLE__
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>
#elif defined(_WIN32)
#include <windows.h>
#include <wincrypt.h>
#endif

namespace cie {
std::vector<CertificateBytes> systemTrustedChain(const CertificateBytes& target,
    const std::vector<CertificateBytes>& candidates, std::time_t now) {
    std::vector<CertificateBytes> result;
#ifdef __APPLE__
    CFMutableArrayRef certificates = CFArrayCreateMutable(nullptr, 0, &kCFTypeArrayCallBacks);
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    SecTrustRef trust = nullptr;
    CFDateRef date = CFDateCreate(nullptr, double(now) - kCFAbsoluteTimeIntervalSince1970);
    auto append = [&](const CertificateBytes& bytes) {
        CFDataRef data = CFDataCreate(nullptr, bytes.data(), CFIndex(bytes.size()));
        SecCertificateRef cert = data ? SecCertificateCreateWithData(nullptr, data) : nullptr;
        if (cert && certificates) CFArrayAppendValue(certificates, cert);
        if (cert) CFRelease(cert);
        if (data) CFRelease(data);
        return cert != nullptr;
    };
    if (certificates && policy && date && append(target)) {
        for (const auto& bytes : candidates) append(bytes);
        if (SecTrustCreateWithCertificates(certificates, policy, &trust) == errSecSuccess &&
            SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess &&
            SecTrustSetVerifyDate(trust, date) == errSecSuccess && SecTrustEvaluateWithError(trust, nullptr)) {
            // Do not replace system anchors with certificates from the document.
            CFArrayRef chain = SecTrustCopyCertificateChain(trust);
            for (CFIndex i = 0; chain && i < CFArrayGetCount(chain); ++i) {
                auto cert = static_cast<SecCertificateRef>(const_cast<void*>(CFArrayGetValueAtIndex(chain, i)));
                CFDataRef bytes = SecCertificateCopyData(cert);
                if (bytes) {
                    result.emplace_back(CFDataGetBytePtr(bytes), CFDataGetBytePtr(bytes) + CFDataGetLength(bytes));
                    CFRelease(bytes);
                }
            }
            if (chain) CFRelease(chain);
        }
    }
    if (trust) CFRelease(trust);
    if (date) CFRelease(date);
    if (policy) CFRelease(policy);
    if (certificates) CFRelease(certificates);
#elif defined(_WIN32)
    HCERTSTORE extra = CertOpenStore(CERT_STORE_PROV_MEMORY, 0, 0, CERT_STORE_CREATE_NEW_FLAG, nullptr);
    PCCERT_CONTEXT leaf = CertCreateCertificateContext(X509_ASN_ENCODING, target.data(), DWORD(target.size()));
    PCCERT_CHAIN_CONTEXT chain = nullptr;
    if (extra && leaf) {
        for (const auto& bytes : candidates)
            CertAddEncodedCertificateToStore(extra, X509_ASN_ENCODING, bytes.data(), DWORD(bytes.size()), CERT_STORE_ADD_USE_EXISTING, nullptr);
        CERT_CHAIN_PARA parameters{}; parameters.cbSize = sizeof(parameters);
        ULARGE_INTEGER ticks{}; ticks.QuadPart = (uint64_t(now) + 11644473600ULL) * 10000000ULL;
        FILETIME date{ticks.LowPart, ticks.HighPart};
        DWORD flags = CERT_CHAIN_CACHE_ONLY_URL_RETRIEVAL | CERT_CHAIN_DISABLE_AUTH_ROOT_AUTO_UPDATE | CERT_CHAIN_DISABLE_AIA;
        // 'extra' supplies untrusted intermediates; the engine uses its own roots.
        if (CertGetCertificateChain(nullptr, leaf, &date, extra, &parameters, flags, nullptr, &chain)) {
            CERT_CHAIN_POLICY_PARA policy{}; policy.cbSize = sizeof(policy);
            CERT_CHAIN_POLICY_STATUS status{}; status.cbSize = sizeof(status);
            if (CertVerifyCertificateChainPolicy(CERT_CHAIN_POLICY_BASE, chain, &policy, &status) &&
                status.dwError == 0 && chain->TrustStatus.dwErrorStatus == 0 && chain->cChain > 0) {
                auto* path = chain->rgpChain[0];
                for (DWORD i = 0; i < path->cElement; ++i) {
                    auto* cert = path->rgpElement[i]->pCertContext;
                    result.emplace_back(cert->pbCertEncoded, cert->pbCertEncoded + cert->cbCertEncoded);
                }
            }
        }
    }
    if (chain) CertFreeCertificateChain(chain);
    if (leaf) CertFreeCertificateContext(leaf);
    if (extra) CertCloseStore(extra, 0);
#else
    // Linux trust integration is intentionally not claimed by this prototype.
    (void)target; (void)candidates; (void)now;
#endif
    return result;
}
}
