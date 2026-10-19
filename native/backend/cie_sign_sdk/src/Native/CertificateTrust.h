// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "Revocation.h"
#include "CertificateValidation.h"
namespace cie {
struct TrustOptions {
    bool useCieAuthorities = true;
    bool useDifesaAuthorities = true;
    bool useSystemTrust = true;
    bool allowNetwork = true;
    bool checkRevocation = true;
    std::time_t now = std::time(nullptr);
    std::vector<CertificateBytes> anchors; // Explicit test/application policy, never CMS/AIA roots.
};
struct CertificateValidation {
    CIE_CERTIFICATE_VALIDATION trust{};
    REVOCATION_INFO leaf{};
    std::vector<CertificateBytes> chain; // Path accepted by policy, for historical evidence checks.
};
std::vector<CertificateBytes> cieIssuerCertificates();
CertificateValidation validateCertificate(const CertificateBytes& target,
    const std::vector<CertificateBytes>& candidates, const HttpOptions& network,
    const TrustOptions& options = {});
// Returns a chain only after the platform's own trust policy accepts it.
std::vector<CertificateBytes> systemTrustedChain(const CertificateBytes& target,
    const std::vector<CertificateBytes>& candidates, std::time_t now);
}
