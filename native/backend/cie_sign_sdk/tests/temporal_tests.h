// SPDX-License-Identifier: BSD-3-Clause
#include "Native/TemporalValidation.h"
#include <openssl/cms.h>
#include "PdfSignatureGenerator.h"
#include "PdfVerifier.h"
#include "SignedDocument.h"
#include <openssl/ts.h>
#include <algorithm>
#include <filesystem>
#include <fstream>
namespace {
int timestampClock(TS_RESP_CTX*,void* value,long* seconds,long* micros) {
    *seconds=long(*static_cast<std::time_t*>(value)); *micros=0; return 1;
}
int timestampExtension(TS_RESP_CTX* ctx,X509_EXTENSION* extension,void*) {
    return TS_TST_INFO_add_ext(TS_RESP_CTX_get_tst_info(ctx),extension,-1);
}
cie::CertificateBytes timestampToken(X509* tsa,EVP_PKEY* key,const cie::CertificateBytes& data,std::time_t when,bool accuracy=true,
    const char* extensionOid=nullptr,bool critical=false,bool duplicate=false) {
    Owned<TS_RESP_CTX,TS_RESP_CTX_free> ctx(TS_RESP_CTX_new(),TS_RESP_CTX_free);
    Owned<ASN1_OBJECT,ASN1_OBJECT_free> policy(OBJ_txt2obj("1.2.3.4.5",1),ASN1_OBJECT_free);
    check(ctx && TS_RESP_CTX_set_signer_cert(ctx.get(),tsa)==1 && TS_RESP_CTX_set_signer_key(ctx.get(),key)==1 &&
        TS_RESP_CTX_set_signer_digest(ctx.get(),EVP_sha256())==1 && TS_RESP_CTX_set_ess_cert_id_digest(ctx.get(),EVP_sha256())==1 &&
        TS_RESP_CTX_set_def_policy(ctx.get(),policy.get())==1 && TS_RESP_CTX_add_md(ctx.get(),EVP_sha256())==1,"TSA response context");
    if(accuracy) check(TS_RESP_CTX_set_accuracy(ctx.get(),1,0,0)==1,"Timestamp accuracy fixture");
    TS_RESP_CTX_set_time_cb(ctx.get(),timestampClock,&when);
    Owned<TS_REQ,TS_REQ_free> request(TS_REQ_new(),TS_REQ_free);
    Owned<TS_MSG_IMPRINT,TS_MSG_IMPRINT_free> imprint(TS_MSG_IMPRINT_new(),TS_MSG_IMPRINT_free);
    Owned<X509_ALGOR,X509_ALGOR_free> algorithm(X509_ALGOR_new(),X509_ALGOR_free);
    X509_ALGOR_set0(algorithm.get(),OBJ_nid2obj(NID_sha256),V_ASN1_NULL,nullptr);
    unsigned char digest[32]; unsigned int size=0; EVP_Digest(data.data(),data.size(),digest,&size,EVP_sha256(),nullptr);
    check(TS_MSG_IMPRINT_set_algo(imprint.get(),algorithm.get())==1 && TS_MSG_IMPRINT_set_msg(imprint.get(),digest,size)==1 &&
        TS_REQ_set_version(request.get(),1)==1 && TS_REQ_set_msg_imprint(request.get(),imprint.get())==1 && TS_REQ_set_cert_req(request.get(),1)==1,"Timestamp request fixture");
    if(extensionOid) {
        Owned<ASN1_OBJECT,ASN1_OBJECT_free> oid(OBJ_txt2obj(extensionOid,1),ASN1_OBJECT_free);
        Owned<ASN1_OCTET_STRING,ASN1_OCTET_STRING_free> value(ASN1_OCTET_STRING_new(),ASN1_OCTET_STRING_free);
        const unsigned char sequence[]={0x30,0x00};
        check(oid && value && ASN1_OCTET_STRING_set(value.get(),sequence,sizeof(sequence))==1,"Timestamp extension value fixture");
        Owned<X509_EXTENSION,X509_EXTENSION_free> ext(X509_EXTENSION_create_by_OBJ(nullptr,oid.get(),critical,value.get()),X509_EXTENSION_free);
        check(ext && TS_REQ_add_ext(request.get(),ext.get(),-1)==1,"Timestamp extension fixture");
        if(duplicate) check(TS_REQ_add_ext(request.get(),ext.get(),-1)==1,"Duplicate timestamp extension fixture");
        TS_RESP_CTX_set_extension_cb(ctx.get(),timestampExtension,nullptr);
    }
    Owned<BIO,BIO_free_all> bio(BIO_new(BIO_s_mem()),BIO_free_all);
    check(i2d_TS_REQ_bio(bio.get(),request.get())==1,"Encode timestamp request");
    Owned<TS_RESP,TS_RESP_free> response(TS_RESP_create_response(ctx.get(),bio.get()),TS_RESP_free);
    auto* token=response ? TS_RESP_get_token(response.get()) : nullptr;
    check(token!=nullptr,"Generate timestamp token");
    int n=i2d_PKCS7(token,nullptr); cie::CertificateBytes bytes(n); auto* p=bytes.data(); i2d_PKCS7(token,&p); return bytes;
}
void testTemporalValidation(const std::filesystem::path& output) {
    auto rootKey=key(); auto root=cert(rootKey.get(),nullptr,nullptr,200,true);
    auto tsaKey=key(); auto tsa=cert(tsaKey.get(),root.get(),rootKey.get(),201);
    extension(tsa.get(),root.get(),NID_ext_key_usage,"critical,timeStamping"); X509_sign(tsa.get(),rootKey.get(),EVP_sha256());
    auto signerKey=key(); auto signer=cert(signerKey.get(),root.get(),rootKey.get(),202);
    X509_gmtime_adj(X509_getm_notAfter(signer.get()),-600); X509_sign(signer.get(),rootKey.get(),EVP_sha256());
    auto now=std::time(nullptr),when=now-1200;
    cie::TemporalOptions options; options.now=now; options.trust.useCieAuthorities=false; options.trust.useSystemTrust=false;
    options.trust.useDifesaAuthorities=false;
    options.trust.allowNetwork=false; options.trust.checkRevocation=false; options.trust.anchors={encode(root.get())};
    cie::HttpOptions offline; offline.allowNetwork=false;
    const char message[]="Historical validation fixture. No identity document or personal data.";
    Owned<BIO,BIO_free_all> content(BIO_new_mem_buf(message,sizeof(message)-1),BIO_free_all);
    Owned<CMS_ContentInfo,CMS_ContentInfo_free> cms(CMS_sign(signer.get(),signerKey.get(),nullptr,content.get(),CMS_BINARY),CMS_ContentInfo_free);
    check(bool(cms),"Generate temporal CMS fixture");
    auto* si=sk_CMS_SignerInfo_value(CMS_get0_SignerInfos(cms.get()),0);
    auto* sig=CMS_SignerInfo_get0_signature(si);
    cie::CertificateBytes signature(ASN1_STRING_get0_data(sig),ASN1_STRING_get0_data(sig)+ASN1_STRING_length(sig));
    auto token=timestampToken(tsa.get(),tsaKey.get(),signature,when);
    auto goodCrl=crl(root.get(),rootKey.get(),nullptr,-2400,3600);
    auto pass=[&](bool condition,const char* label){ check(condition,label); std::cout<<"PASS "<<label<<'\n'; };
    auto result=cie::validateTimestamp(token,signature,{goodCrl},offline,options);
    pass(result.timestampStatus==CIE_TS_VERIFIED && result.tsaRevocationStatus==REVOCATION_STATUS_GOOD,"timestamp imprint signature ESS TSA chain and archived revocation verified");
    auto wrong=signature; wrong[0]^=1;
    pass(cie::validateTimestamp(token,wrong,{goodCrl},offline,options).timestampStatus==CIE_TS_INVALID,"timestamp wrong imprint rejected");
    auto corrupted=token; corrupted.back()^=1;
    pass(cie::validateTimestamp(corrupted,signature,{goodCrl},offline,options).timestampStatus!=CIE_TS_VERIFIED,"forged timestamp signature rejected");
    auto untrusted=options; untrusted.trust.anchors.clear();
    pass(cie::validateTimestamp(token,signature,{goodCrl},offline,untrusted).timestampStatus==CIE_TS_INDETERMINATE,"embedded TSA root never trusted implicitly");
    auto extended=timestampToken(tsa.get(),tsaKey.get(),signature,when,true,"1.3.6.1.5.5.7.1.3");
    auto extensionResult=cie::validateTimestamp(extended,signature,{goodCrl},offline,options);
    pass(extensionResult.timestampStatus==CIE_TS_VERIFIED && extensionResult.tsaRevocationStatus==REVOCATION_STATUS_GOOD,
        "noncritical timestamp extension retains signature trust and revocation checks");
    auto unknownExtension=timestampToken(tsa.get(),tsaKey.get(),signature,when,true,"1.2.3.4.9876");
    pass(cie::validateTimestamp(unknownExtension,signature,{goodCrl},offline,options).timestampStatus==CIE_TS_VERIFIED,
        "unknown noncritical timestamp metadata is permitted");
    pass(cie::validateTimestamp(extended,signature,{goodCrl},offline,untrusted).timestampStatus==CIE_TS_INDETERMINATE,
        "noncritical timestamp extension never grants TSA trust");
    pass(cie::validateTimestamp(extended,wrong,{goodCrl},offline,options).timestampStatus==CIE_TS_INVALID,
        "noncritical timestamp extension cannot bypass imprint verification");
    auto criticalToken=timestampToken(tsa.get(),tsaKey.get(),signature,when,true,"1.2.3.4.9876",true);
    auto criticalResult=cie::validateTimestamp(criticalToken,signature,{goodCrl},offline,options);
    pass(criticalResult.timestampStatus==CIE_TS_INDETERMINATE &&
        !std::strcmp(criticalResult.timestampReason,"timestamp_critical_extension_unsupported"),
        "unsupported critical timestamp extension is indeterminate never verified");
    auto duplicateToken=timestampToken(tsa.get(),tsaKey.get(),signature,when,true,"1.2.3.4.9876",false,true);
    auto duplicateResult=cie::validateTimestamp(duplicateToken,signature,{goodCrl},offline,options);
    pass(duplicateResult.timestampStatus==CIE_TS_INVALID &&
        !std::strcmp(duplicateResult.timestampReason,"timestamp_duplicate_extension"),"duplicate timestamp extension rejected");
    // Alter the signed extension bytes while retaining a well-formed token.
    const auto* extCursor=extended.data();
    Owned<PKCS7,PKCS7_free> altered(d2i_PKCS7(nullptr,&extCursor,long(extended.size())),PKCS7_free);
    check(altered && altered->d.sign->contents->d.other &&
        altered->d.sign->contents->d.other->type==V_ASN1_OCTET_STRING,"Timestamp content fixture");
    auto* encodedInfo=altered->d.sign->contents->d.other->value.octet_string;
    Owned<TS_TST_INFO,TS_TST_INFO_free> alteredInfo(PKCS7_to_TS_TST_INFO(altered.get()),TS_TST_INFO_free);
    check(bool(alteredInfo),"Decode timestamp extension tamper fixture");
    auto* extValue=X509_EXTENSION_get_data(TS_TST_INFO_get_ext(alteredInfo.get(),0));
    const unsigned char changedValue[]={0x30,0x02,0x05,0x00};
    check(ASN1_OCTET_STRING_set(extValue,changedValue,sizeof(changedValue))==1,"Change signed timestamp extension");
    int infoSize=i2d_TS_TST_INFO(alteredInfo.get(),nullptr); cie::CertificateBytes infoBytes(infoSize); auto* infoOut=infoBytes.data();
    i2d_TS_TST_INFO(alteredInfo.get(),&infoOut); ASN1_STRING_set(encodedInfo,infoBytes.data(),infoSize);
    int alteredSize=i2d_PKCS7(altered.get(),nullptr); cie::CertificateBytes alteredBytes(alteredSize); auto* alteredOut=alteredBytes.data();
    i2d_PKCS7(altered.get(),&alteredOut);
    pass(cie::validateTimestamp(alteredBytes,signature,{goodCrl},offline,options).timestampStatus==CIE_TS_INVALID,
        "signed timestamp extension tampering rejected");
    auto future=timestampToken(tsa.get(),tsaKey.get(),signature,now+3600);
    pass(cie::validateTimestamp(future,signature,{goodCrl},offline,options).timestampStatus==CIE_TS_INVALID,"future timestamp rejected");
    auto noAccuracy=timestampToken(tsa.get(),tsaKey.get(),signature,when,false);
    auto uncertain=cie::validateTimestamp(noAccuracy,signature,{goodCrl},offline,options);
    pass(uncertain.timestampStatus==CIE_TS_VERIFIED && uncertain.historicalStatus==CIE_HISTORY_INDETERMINATE &&
        !std::strcmp(uncertain.historicalReason,"timestamp_accuracy_missing_or_unsupported"),"unspecified timestamp accuracy cannot establish historical validity");
    auto encodeCms=[&] { int n=i2d_CMS_ContentInfo(cms.get(),nullptr); cie::CertificateBytes b(n); auto* p=b.data(); i2d_CMS_ContentInfo(cms.get(),&p); return b; };
    auto verify=[&](bool valid=true){return cie::validateCmsTemporal(encodeCms(),encode(signer.get()),signature,valid,offline,options);};
    auto absent=verify();
    pass(absent.timestampStatus==CIE_TS_ABSENT && absent.historicalStatus==CIE_HISTORY_INDETERMINATE,"declared signing time does not establish historical validity");
    check(CMS_unsigned_add1_attr_by_NID(si,NID_id_smime_aa_timeStampToken,V_ASN1_SEQUENCE,token.data(),int(token.size()))==1,"Attach timestamp fixture");
    auto missing=verify();
    pass(missing.timestampStatus==CIE_TS_VERIFIED && missing.historicalStatus==CIE_HISTORY_INDETERMINATE,"valid timestamp without archived revocation remains indeterminate");
    const auto* cursor=goodCrl.data(); Owned<X509_CRL,X509_CRL_free> decoded(d2i_X509_CRL(nullptr,&cursor,long(goodCrl.size())),X509_CRL_free);
    check(CMS_add1_crl(cms.get(),decoded.get())==1,"Embed complete archived CRL");
    auto encodedLegacy=encodeCms(); CSignedDocument legacy(encodedLegacy.data(),int(encodedLegacy.size()));
    pass(legacy.getSignerCount()==1,"legacy SDK parses CMS signer after optional embedded CRLs");
    auto historical=verify();
    pass(historical.historicalStatus==CIE_HISTORY_VALID && historical.referenceTime==when,"expired today but valid at trusted timestamp with archived complete CRLs");
    pass(verify(false).historicalStatus==CIE_HISTORY_INVALID,"timestamp cannot repair invalid document signature");
    // Export synthetic fixtures: test roots remain untrusted in the public ABI.
    if(!output.empty()) {
        std::filesystem::create_directories(output); auto bytes=encodeCms();
        std::ofstream file(output/"timestamped-untrusted.p7m",std::ios::binary); file.write(reinterpret_cast<const char*>(bytes.data()),bytes.size());
        std::ofstream tst(output/"signature-timestamp.der",std::ios::binary); tst.write(reinterpret_cast<const char*>(token.data()),token.size());
    }
    auto revokedCrl=crl(root.get(),rootKey.get(),signer.get(),-2400,3600);
    cursor=revokedCrl.data(); decoded.reset(d2i_X509_CRL(nullptr,&cursor,long(revokedCrl.size())));
    CMS_add1_crl(cms.get(),decoded.get());
    pass(verify().historicalStatus==CIE_HISTORY_INVALID,"archived revocation overrides good CRL and timestamp");
    auto* removed=CMS_unsigned_delete_attr(si,0); X509_ATTRIBUTE_free(removed);
    CMS_unsigned_add1_attr_by_NID(si,NID_id_smime_aa_timeStampToken,V_ASN1_SEQUENCE,token.data(),int(token.size()));
    X509_ATTRIBUTE* duplicate=X509_ATTRIBUTE_create_by_NID(nullptr,NID_id_smime_aa_timeStampToken,V_ASN1_SEQUENCE,token.data(),int(token.size()));
    // OpenSSL merges duplicates on add1; put two values explicitly to test ambiguity.
    auto* attr=CMS_unsigned_get_attr(si,0); auto* type=X509_ATTRIBUTE_get0_type(duplicate,0);
    check(X509_ATTRIBUTE_set1_data(attr,V_ASN1_SEQUENCE,ASN1_STRING_get0_data(type->value.sequence),ASN1_STRING_length(type->value.sequence))==1,"Duplicate timestamp fixture");
    X509_ATTRIBUTE_free(duplicate);
    pass(verify().timestampStatus==CIE_TS_INVALID,"ambiguous signature timestamps rejected");
    // PDF DocTimeStamp is distinct from a document signature.
    PoDoFo::PdfMemDocument pdf; pdf.GetPages().CreatePage(PoDoFo::Rect(0,0,595,842));
    PoDoFo::charbuff buffer; PoDoFo::BufferStreamDevice device(buffer); pdf.Save(device);
    PdfSignatureGenerator generator; check(generator.Load(buffer.data(),int(buffer.size()))==0,"Load document timestamp PDF");
    generator.InitSignature(0,"Test",nullptr,"Synthetic TSA",nullptr,nullptr,nullptr,"DocTimeStamp","ETSI.RFC3161");
    UUCByteArray bytesToStamp; generator.GetBufferForSignature(bytesToStamp);
    auto documentToken=timestampToken(tsa.get(),tsaKey.get(),{bytesToStamp.getContent(),bytesToStamp.getContent()+bytesToStamp.getLength()},when);
    generator.SetSignature(reinterpret_cast<const char*>(documentToken.data()),int(documentToken.size()));
    UUCByteArray stampedPdf; generator.GetSignedPdf(stampedPdf);
    PDFVerifier pdfVerifier; check(pdfVerifier.Load(reinterpret_cast<const char*>(stampedPdf.getContent()),int(stampedPdf.getLength()))==0,"Parse document timestamp PDF");
    auto documentResult=pdfVerifier.VerifyDocumentTimestamps(offline,options);
    pass(pdfVerifier.GetNumberOfSignatures()==0 && documentResult.timestampCount==1 &&
        documentResult.timestampStatus==CIE_TS_VERIFIED && documentResult.historicalStatus==CIE_HISTORY_INDETERMINATE,
        "PDF final-revision timestamp bound to ByteRange and separate from signer validity");
    if(!output.empty()) {
        std::ofstream pdfFile(output/"document-timestamp-untrusted.pdf",std::ios::binary);
        pdfFile.write(reinterpret_cast<const char*>(stampedPdf.getContent()),stampedPdf.getLength());
    }
    std::vector<char> modified(stampedPdf.getContent(),stampedPdf.getContent()+stampedPdf.getLength());
    auto header=std::search(modified.begin(),modified.end(),"%PDF-","%PDF-"+5);
    check(header!=modified.end(),"PDF header fixture"); header[7]=header[7]=='7' ? '6' : '7';
    check(pdfVerifier.Load(modified.data(),int(modified.size()))==0,"Parse altered stamped PDF");
    pass(pdfVerifier.VerifyDocumentTimestamps(offline,options).timestampStatus==CIE_TS_INVALID,"PDF document timestamp rejects altered signed bytes");
    // Same token after an unsigned append is outside the supported final-revision scope.
    modified.assign(stampedPdf.getContent(),stampedPdf.getContent()+stampedPdf.getLength()); modified.push_back(' ');
    check(pdfVerifier.Load(modified.data(),int(modified.size()))==0,"Parse appended stamped PDF");
    pass(pdfVerifier.VerifyDocumentTimestamps(offline,options).timestampStatus==CIE_TS_INDETERMINATE,"earlier PDF revision timestamp does not validate later unsigned bytes");
    PdfSignatureGenerator pdfSigner; check(pdfSigner.Load(buffer.data(),int(buffer.size()))==0,"Load signature timestamp PDF");
    pdfSigner.InitSignature(0,"Test",nullptr,"Synthetic signer",nullptr,nullptr,nullptr,"Signature","ETSI.CAdES.detached");
    UUCByteArray bytesToSign; pdfSigner.GetBufferForSignature(bytesToSign);
    Owned<BIO,BIO_free_all> pdfContent(BIO_new_mem_buf(bytesToSign.getContent(),int(bytesToSign.getLength())),BIO_free_all);
    Owned<CMS_ContentInfo,CMS_ContentInfo_free> pdfCms(CMS_sign(signer.get(),signerKey.get(),nullptr,pdfContent.get(),CMS_BINARY|CMS_DETACHED),CMS_ContentInfo_free);
    check(bool(pdfCms),"PDF CMS fixture"); auto* pdfSi=sk_CMS_SignerInfo_value(CMS_get0_SignerInfos(pdfCms.get()),0);
    auto* pdfSignature=CMS_SignerInfo_get0_signature(pdfSi);
    auto pdfToken=timestampToken(tsa.get(),tsaKey.get(),{ASN1_STRING_get0_data(pdfSignature),ASN1_STRING_get0_data(pdfSignature)+ASN1_STRING_length(pdfSignature)},when);
    check(CMS_unsigned_add1_attr_by_NID(pdfSi,NID_id_smime_aa_timeStampToken,V_ASN1_SEQUENCE,pdfToken.data(),int(pdfToken.size()))==1,"Attach PDF signature timestamp");
    cursor=goodCrl.data(); decoded.reset(d2i_X509_CRL(nullptr,&cursor,long(goodCrl.size()))); CMS_add1_crl(pdfCms.get(),decoded.get());
    int cmsSize=i2d_CMS_ContentInfo(pdfCms.get(),nullptr); cie::CertificateBytes pdfEncoded(cmsSize); auto* pdfOut=pdfEncoded.data(); i2d_CMS_ContentInfo(pdfCms.get(),&pdfOut);
    pdfSigner.SetSignature(reinterpret_cast<const char*>(pdfEncoded.data()),int(pdfEncoded.size()));
    UUCByteArray signaturePdf; pdfSigner.GetSignedPdf(signaturePdf);
    check(pdfVerifier.Load(reinterpret_cast<const char*>(signaturePdf.getContent()),int(signaturePdf.getLength()))==0,"Load timestamped PAdES");
    char signatureType[256]{}; int validPdf=pdfVerifier.VerifySignature(0,nullptr,signatureType,nullptr);
    pass(validPdf>=0 && (validPdf&VERIFIED_SIGNATURE),"PAdES signature with timestamp and embedded CRL retains cryptographic integrity");
    if(!output.empty()) {
        std::ofstream file(output/"signature-timestamp-untrusted.pdf",std::ios::binary);
        file.write(reinterpret_cast<const char*>(signaturePdf.getContent()),signaturePdf.getLength());
    }
    auto forgedCrl=goodCrl; forgedCrl.back()^=1;
    pass(cie::validateTimestamp(token,signature,{forgedCrl},offline,options).tsaRevocationStatus!=REVOCATION_STATUS_GOOD,"forged archived CRL cannot authorize historical validation");
    auto noCurrentCrl=crl(root.get(),rootKey.get(),nullptr,-2400,-300);
    auto expiredEvidence=cie::validateTimestamp(token,signature,{noCurrentCrl},offline,options);
    pass(expiredEvidence.tsaRevocationStatus==REVOCATION_STATUS_GOOD &&
        !std::strcmp(expiredEvidence.historicalReason,"tsa_current_status_missing_requires_archive_renewal_proof"),
        "historical TSA evidence alone cannot authorize backdated tokens");
    // Replace the embedded TSA certificate with a same-key different certificate.
    const auto* cp=token.data(); Owned<PKCS7,PKCS7_free> parsed(d2i_PKCS7(nullptr,&cp,long(token.size())),PKCS7_free);
    auto* embedded=sk_X509_value(parsed->d.sign->cert,0);
    X509_gmtime_adj(X509_getm_notAfter(embedded),172800); X509_sign(embedded,rootKey.get(),EVP_sha256());
    int n=i2d_PKCS7(parsed.get(),nullptr); cie::CertificateBytes changed(n); auto* dest=changed.data(); i2d_PKCS7(parsed.get(),&dest);
    pass(cie::validateTimestamp(changed,signature,{goodCrl},offline,options).timestampStatus==CIE_TS_INVALID,"timestamp ESS certificate binding rejects substituted same-key certificate");
    int ekuIndex=X509_get_ext_by_NID(embedded,NID_ext_key_usage,-1);
    X509_EXTENSION_free(X509_delete_ext(embedded,ekuIndex)); X509_sign(embedded,rootKey.get(),EVP_sha256());
    n=i2d_PKCS7(parsed.get(),nullptr); changed.resize(n); dest=changed.data(); i2d_PKCS7(parsed.get(),&dest);
    pass(cie::validateTimestamp(changed,signature,{goodCrl},offline,options).timestampStatus==CIE_TS_INVALID,"TSA without critical exclusive timestamping EKU rejected");
    auto badTsaCrl=crl(root.get(),rootKey.get(),tsa.get(),-2400,3600);
    pass(cie::validateTimestamp(token,signature,{badTsaCrl},offline,options).tsaRevocationStatus==REVOCATION_STATUS_REVOKED,"TSA historical revocation never becomes good");
    auto stale=crl(root.get(),rootKey.get(),nullptr,-3600,-2400);
    pass(cie::validateTimestamp(token,signature,{stale},offline,options).tsaRevocationStatus==REVOCATION_STATUS_UNKNOWN,"CRL outside timestamp interval remains unknown");
}
}
