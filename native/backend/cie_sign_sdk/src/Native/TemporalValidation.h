// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "CertificateTrust.h"
#include "../../include/TemporalValidation.h"
namespace cie {
// Only authenticated complete CRLs embedded in CMS containers are consumed.
// No current online response is reinterpreted as historical evidence.
struct TemporalOptions {
    TrustOptions trust;
    std::time_t now = std::time(nullptr);
};
CIE_TEMPORAL_VALIDATION validateTimestamp(const CertificateBytes& token,
    const CertificateBytes& stampedBytes, const std::vector<CertificateBytes>& crls,
    const HttpOptions& network, const TemporalOptions& options = {});
CIE_TEMPORAL_VALIDATION validateCmsTemporal(const CertificateBytes& cms,
    const CertificateBytes& signerCertificate, const CertificateBytes& signature,
    bool signatureValid, const HttpOptions& network, const TemporalOptions& options = {});
}
