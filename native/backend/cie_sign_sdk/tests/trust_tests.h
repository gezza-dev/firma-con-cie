// SPDX-License-Identifier: BSD-3-Clause
// Uses the independent certificate fixtures defined by security_tests.cpp.
#include "Native/CertificateTrust.h"
static void testCertificateTrust()
{
    auto rootKey = key(); auto root = cert(rootKey.get(), nullptr, nullptr, 100, true);
    auto subKey = key(); auto sub = cert(subKey.get(), root.get(), rootKey.get(), 101, true);
    auto leafKey = key(); auto leaf = cert(leafKey.get(), sub.get(), subKey.get(), 102);
    cie::TrustOptions options; options.useCieAuthorities = false; options.useSystemTrust = false;
    options.useDifesaAuthorities = false;
    options.allowNetwork = false; options.checkRevocation = false; options.anchors = {encode(root.get())};
    auto run = [&](X509* target, const std::vector<cie::CertificateBytes>& candidates,
                   uint32_t expected, const char* label) {
        auto result = cie::validateCertificate(encode(target), candidates, {}, options);
        check(result.trust.status == expected, label); std::cout << "PASS " << label << '\n';
        return result;
    };
    auto valid = run(leaf.get(), {encode(sub.get())}, CIE_TRUST_TRUSTED, "trusted root and complete intermediate path");
    check(valid.trust.chainLength == 3, "Complete path includes three certificates");
    auto applicationPolicy=options;applicationPolicy.useCieAuthorities=true;applicationPolicy.useDifesaAuthorities=true;
    auto explicitPath=cie::validateCertificate(encode(leaf.get()),{encode(sub.get())},{},applicationPolicy);
    check(explicitPath.trust.status==CIE_TRUST_TRUSTED && !std::strcmp(explicitPath.trust.trustSource,"explicit_policy"),
        "Authority source must identify the accepted anchor");
    std::cout<<"PASS explicit anchor is not mislabeled as a ministry or system root\n";
    applicationPolicy.anchors.clear();
    check(cie::validateCertificate(encode(leaf.get()),{encode(sub.get()),encode(root.get())},{},applicationPolicy).trust.status!=CIE_TRUST_TRUSTED,
        "Official authority catalogs cannot trust arbitrary embedded roots");
    std::cout<<"PASS official authority catalogs never trust arbitrary document roots\n";
    run(leaf.get(), {}, CIE_TRUST_UNKNOWN, "missing intermediate never becomes trusted");
    options.anchors.clear();
    run(leaf.get(), {encode(sub.get()), encode(root.get())}, CIE_TRUST_UNTRUSTED,
        "embedded self-signed root never becomes an anchor");
    options.useSystemTrust = true;
    run(leaf.get(), {encode(sub.get()), encode(root.get())}, CIE_TRUST_UNTRUSTED,
        "native trust policy rejects embedded private root");
    options.useSystemTrust = false; options.anchors = {encode(root.get())};
    auto wrongKey = key(); auto wrongRoot = cert(wrongKey.get(), nullptr, nullptr, 103, true);
    options.anchors = {encode(wrongRoot.get())};
    auto wrong = cie::validateCertificate(encode(leaf.get()), {encode(sub.get()), encode(root.get())}, {}, options);
    check(wrong.trust.status != CIE_TRUST_TRUSTED, "Unrelated root must fail");
    std::cout << "PASS unrelated root rejected\n";
    options.anchors = {encode(root.get())};
    X509_gmtime_adj(X509_getm_notAfter(leaf.get()), -600); X509_sign(leaf.get(), subKey.get(), EVP_sha256());
    run(leaf.get(), {encode(sub.get())}, CIE_TRUST_INVALID, "expired leaf rejected at current time");
    X509_gmtime_adj(X509_getm_notAfter(leaf.get()), 86400); X509_sign(leaf.get(), subKey.get(), EVP_sha256());
    X509_gmtime_adj(X509_getm_notAfter(sub.get()), -600); X509_sign(sub.get(), rootKey.get(), EVP_sha256());
    run(leaf.get(), {encode(sub.get())}, CIE_TRUST_INVALID, "expired intermediate rejected");
    X509_gmtime_adj(X509_getm_notAfter(sub.get()), 86400); X509_sign(sub.get(), rootKey.get(), EVP_sha256());
    auto forged = encode(leaf.get()); forged.back() ^= 1;
    check(cie::validateCertificate(forged, {encode(sub.get())}, {}, options).trust.status == CIE_TRUST_INVALID,
        "Forged certificate signature must fail");
    std::cout << "PASS altered certificate signature rejected\n";
    auto nonCa = cert(subKey.get(), root.get(), rootKey.get(), 104, false);
    auto badLeaf = cert(leafKey.get(), nonCa.get(), subKey.get(), 105);
    run(badLeaf.get(), {encode(nonCa.get())}, CIE_TRUST_INVALID, "non-CA issuer rejected");
    int usage = X509_get_ext_by_NID(leaf.get(), NID_key_usage, -1);
    X509_EXTENSION_free(X509_delete_ext(leaf.get(), usage));
    extension(leaf.get(), sub.get(), NID_key_usage, "critical,keyEncipherment");
    X509_sign(leaf.get(), subKey.get(), EVP_sha256());
    run(leaf.get(), {encode(sub.get())}, CIE_TRUST_INVALID, "certificate without document-signing usage rejected");
    leaf = cert(leafKey.get(), sub.get(), subKey.get(), 106);
    options.checkRevocation = true;
    auto offline = run(leaf.get(), {encode(sub.get())}, CIE_TRUST_TRUSTED,
        "offline trusted chain keeps revocation unknown");
    check(offline.leaf.nRevocationStatus == REVOCATION_STATUS_UNKNOWN &&
        offline.trust.revocationStatus == REVOCATION_STATUS_UNKNOWN,
        "Offline status cannot become not-revoked");
    cie::HttpOptions disabled; disabled.allowNetwork = false;
    check(cie::httpRequest("https://example.invalid/", {}, nullptr, disabled).error == CURLE_OPERATION_TIMEDOUT,
        "Disabled network must perform no request");
    std::cout << "PASS network-disabled operation fails closed\n";

    // End-to-end chain revocation, with signed wire-format responses and no
    // live responder. This tests aggregation, not only ASN.1 response parsing.
    auto onlineLeaf = cert(leafKey.get(), sub.get(), subKey.get(), 107);
    extension(onlineLeaf.get(), sub.get(), NID_info_access, "OCSP;URI:http://test.invalid/leaf");
    X509_sign(onlineLeaf.get(), subKey.get(), EVP_sha256());
    extension(sub.get(), root.get(), NID_crl_distribution_points, "URI:http://test.invalid/root.crl");
    X509_sign(sub.get(), rootKey.get(), EVP_sha256());
    options.allowNetwork = true;
    bool revokeSub = false, forgeCrl = false, revokeLeaf = false, unavailable = false;
    int rootRequests=0;
    bool failRootOnce=false,failRootAlways=false,staleRoot=false;
    bool tlsError=false,httpUnavailable=false,httpPermanent=false;
    cie::HttpOptions transport;
    transport.transport = [&](const std::string& url, const cie::CertificateBytes&, const char*) {
        cie::HttpResponse reply;
        if (unavailable) { reply.error = CURLE_COULDNT_CONNECT; return reply; }
        reply.error = CURLE_OK; reply.status = 200;
        if (url == "http://test.invalid/leaf")
            reply.body = ocsp(onlineLeaf.get(), sub.get(), sub.get(), subKey.get(),
                revokeLeaf ? V_OCSP_CERTSTATUS_REVOKED : V_OCSP_CERTSTATUS_GOOD);
        else if (url == "http://test.invalid/root.crl") {
            ++rootRequests;
            if(tlsError) reply.error=CURLE_PEER_FAILED_VERIFICATION;
            else if(httpPermanent) { reply.error=CURLE_HTTP_RETURNED_ERROR;reply.status=404; }
            else if(httpUnavailable && rootRequests==1) { reply.error=CURLE_HTTP_RETURNED_ERROR;reply.status=503; }
            else if(failRootAlways || (failRootOnce && rootRequests==1)) { reply.error=CURLE_RECV_ERROR;reply.body.clear(); }
            else reply.body = crl(root.get(), forgeCrl ? wrongKey.get() : rootKey.get(), revokeSub ? sub.get() : nullptr,
                staleRoot ? -7200 : -30,staleRoot ? -3600 : 3600);
        }
        else reply.error = CURLE_HTTP_RETURNED_ERROR;
        return reply;
    };
    auto wire = [&] { return cie::validateCertificate(encode(onlineLeaf.get()), {encode(sub.get())}, transport, options); };
    auto good = wire();
    check(good.trust.status == CIE_TRUST_TRUSTED && good.leaf.nRevocationStatus == REVOCATION_STATUS_GOOD &&
        good.trust.revocationStatus == REVOCATION_STATUS_GOOD, "Authenticated full chain revocation good");
    std::cout << "PASS full chain OCSP and CRL good\n";
    failRootOnce=true;rootRequests=0;
    check(wire().trust.revocationStatus==REVOCATION_STATUS_GOOD && rootRequests==2,"Transient root CRL download recovers within retry budget");
    std::cout<<"PASS transient root CRL transport failure recovers with one bounded retry\n";
    failRootOnce=false;failRootAlways=true;rootRequests=0;
    check(wire().trust.revocationStatus==REVOCATION_STATUS_UNKNOWN && rootRequests==2,"Permanent root CRL transport failure remains unknown");
    std::cout<<"PASS persistent root CRL transport failure remains unknown after bounded retry\n";
    failRootAlways=false;staleRoot=true;rootRequests=0;
    check(wire().trust.revocationStatus==REVOCATION_STATUS_UNKNOWN && rootRequests==1,"Stale root CRL cannot trigger transport recovery");
    std::cout<<"PASS expired root CRL is not accepted or retried as a transport error\n";
    staleRoot=false;
    tlsError=true;rootRequests=0;
    check(wire().trust.revocationStatus==REVOCATION_STATUS_UNKNOWN && rootRequests==1,"TLS authentication failure must not be retried or ignored");
    std::cout<<"PASS TLS peer verification failure remains unknown without retry or bypass\n";
    tlsError=false;httpPermanent=true;rootRequests=0;
    check(wire().trust.revocationStatus==REVOCATION_STATUS_UNKNOWN && rootRequests==1,"Permanent HTTP error must not be retried");
    std::cout<<"PASS permanent root CRL HTTP failure is not retried\n";
    httpPermanent=false;httpUnavailable=true;rootRequests=0;
    check(wire().trust.revocationStatus==REVOCATION_STATUS_GOOD && rootRequests==2,"Temporary HTTP 503 may recover within budget");
    std::cout<<"PASS transient root CRL HTTP failure recovers with one bounded retry\n";
    httpUnavailable=false;
    revokeSub = true;
    check(wire().trust.revocationStatus == REVOCATION_STATUS_REVOKED, "Revoked intermediate must revoke chain");
    std::cout << "PASS revoked intermediate overrides good leaf OCSP\n";
    revokeSub = false; forgeCrl = true;
    rootRequests=0;
    auto forgedCrl = wire();
    check(forgedCrl.leaf.nRevocationStatus == REVOCATION_STATUS_GOOD &&
        forgedCrl.trust.revocationStatus == REVOCATION_STATUS_UNKNOWN && rootRequests==1, "Forged issuer CRL cannot bless chain or trigger transport retry");
    std::cout << "PASS forged intermediate CRL keeps chain unknown\n";
    forgeCrl = false; revokeLeaf = true;
    check(wire().trust.revocationStatus == REVOCATION_STATUS_REVOKED, "Revoked leaf must revoke chain");
    std::cout << "PASS revoked leaf overrides good CA CRL\n";
    revokeLeaf = false; unavailable = true;
    auto failed = wire();
    check(failed.trust.status == CIE_TRUST_TRUSTED && failed.trust.revocationStatus == REVOCATION_STATUS_UNKNOWN &&
        failed.leaf.nRevocationStatus == REVOCATION_STATUS_UNKNOWN, "Unavailable responder cannot report good");
    std::cout << "PASS unavailable responder remains unknown on trusted chain\n";
}
