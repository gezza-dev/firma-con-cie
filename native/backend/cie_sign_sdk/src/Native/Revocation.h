// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "HttpClient.h"
#include "disigonsdk.h"
#include <ctime>
#include <openssl/ocsp.h>
#include <vector>
namespace cie {
using CertificateBytes = std::vector<unsigned char>;
CertificateBytes findCertificateIssuer(const CertificateBytes& certificate,
    const std::vector<CertificateBytes>& candidates, const HttpOptions& network);
// Certificate candidates are untrusted. An issuer must cryptographically
// verify the target certificate before it can authorize OCSP/CRL responses.
int verifyOcspResponse(const CertificateBytes& response, X509* target, X509* issuer,
    OCSP_REQUEST* request, REVOCATION_INFO* information, std::time_t now);
int verifyCrlResponse(const CertificateBytes& response, X509* target, X509* issuer,
    REVOCATION_INFO* information, std::time_t now);
int checkRevocation(const CertificateBytes& certificate,
                    const std::vector<CertificateBytes>& candidates,
                    const HttpOptions& network, REVOCATION_INFO* information,
                    std::time_t now = std::time(nullptr));
}
