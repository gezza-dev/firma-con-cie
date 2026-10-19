// SPDX-License-Identifier: BSD-3-Clause
package it.cieid.ltv;

import eu.europa.esig.dss.enumerations.*;
import eu.europa.esig.dss.model.*;
import eu.europa.esig.dss.model.x509.CertificateToken;
import eu.europa.esig.dss.spi.x509.*;
import eu.europa.esig.dss.spi.x509.tsp.TSPSource;
import eu.europa.esig.dss.spi.validation.CommonCertificateVerifier;
import eu.europa.esig.dss.crl.CRLUtils;
import eu.europa.esig.dss.spi.x509.revocation.crl.CRLToken;
import eu.europa.esig.dss.alert.SilentOnStatusAlert;
import eu.europa.esig.dss.pades.PAdESSignatureParameters;
import eu.europa.esig.dss.pades.signature.PAdESService;
import eu.europa.esig.dss.cades.CAdESSignatureParameters;
import eu.europa.esig.dss.cades.signature.CAdESService;
import org.apache.pdfbox.pdmodel.*;
import org.bouncycastle.asn1.*;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.*;
import org.bouncycastle.asn1.nist.NISTObjectIdentifiers;
import org.bouncycastle.cert.*;
import org.bouncycastle.cert.jcajce.*;
import org.bouncycastle.cms.*;
import org.bouncycastle.cms.jcajce.*;
import org.bouncycastle.operator.jcajce.*;
import org.bouncycastle.tsp.*;
import org.bouncycastle.util.CollectionStore;
import java.security.*;
import java.security.cert.X509Certificate;
import java.math.BigInteger;
import java.nio.file.*;
import java.io.*;
import java.time.Instant;
import java.util.*;

/** Synthetic local PKI only. Never install its roots or use real card material. */
public final class LtvSelfTest {
    record Identity(KeyPair key, X509Certificate cert) {}
    static Date date(String value) { return Date.from(Instant.parse(value)); }
    static Identity identity(String name, int serial, Identity issuer, boolean ca, boolean tsa, String until) throws Exception {
        return identity(name,serial,issuer,ca,tsa,until,null);
    }
    static Identity identity(String name, int serial, Identity issuer, boolean ca, boolean tsa, String until, String crlUrl) throws Exception {
        var keys=KeyPairGenerator.getInstance("RSA"); keys.initialize(2048); var pair=keys.generateKeyPair();
        var subject=new X500Name("CN="+name+",O=Synthetic CIE LTV tests,C=IT");
        var owner=issuer==null ? subject : X500Name.getInstance(issuer.cert.getSubjectX500Principal().getEncoded());
        var builder=new JcaX509v3CertificateBuilder(owner,BigInteger.valueOf(serial),date("2023-01-01T00:00:00Z"),date(until),subject,pair.getPublic());
        builder.addExtension(Extension.basicConstraints,true,new BasicConstraints(ca));
        builder.addExtension(Extension.keyUsage,true,new KeyUsage(ca ? KeyUsage.keyCertSign|KeyUsage.cRLSign : KeyUsage.digitalSignature|KeyUsage.nonRepudiation));
        if(crlUrl!=null) builder.addExtension(Extension.cRLDistributionPoints,false,new CRLDistPoint(new DistributionPoint[]{
            new DistributionPoint(new DistributionPointName(new GeneralNames(new GeneralName(GeneralName.uniformResourceIdentifier,crlUrl))),null,null)}));
        if(tsa) builder.addExtension(Extension.extendedKeyUsage,true,new org.bouncycastle.asn1.x509.ExtendedKeyUsage(KeyPurposeId.id_kp_timeStamping));
        var utility=new JcaX509ExtensionUtils();
        builder.addExtension(Extension.subjectKeyIdentifier,false,utility.createSubjectKeyIdentifier(pair.getPublic()));
        builder.addExtension(Extension.authorityKeyIdentifier,false,utility.createAuthorityKeyIdentifier(issuer==null ? pair.getPublic() : issuer.key.getPublic()));
        var signer=new JcaContentSignerBuilder("SHA256withRSA").build(issuer==null ? pair.getPrivate() : issuer.key.getPrivate());
        return new Identity(pair,new JcaX509CertificateConverter().getCertificate(builder.build(signer)));
    }
    static byte[] crl(Identity issuer,String from,String until,Identity revoked) throws Exception {
        var builder=new X509v2CRLBuilder(X500Name.getInstance(issuer.cert.getSubjectX500Principal().getEncoded()),date(from)); builder.setNextUpdate(date(until));
        builder.addExtension(Extension.authorityKeyIdentifier,false,new JcaX509ExtensionUtils().createAuthorityKeyIdentifier(issuer.key.getPublic()));
        builder.addExtension(Extension.cRLNumber,false,new CRLNumber(BigInteger.valueOf(date(from).getTime()/1000)));
        if(revoked!=null) builder.addCRLEntry(revoked.cert.getSerialNumber(),date(from),CRLReason.keyCompromise);
        return builder.build(new JcaContentSignerBuilder("SHA256withRSA").build(issuer.key.getPrivate())).getEncoded();
    }
    static TSPSource tsa(Identity identity,Identity root,String when) {
        return (algorithm,digest) -> {
            try {
                var provider=new JcaDigestCalculatorProviderBuilder().build();
                var attrs=new Hashtable<ASN1ObjectIdentifier,org.bouncycastle.asn1.cms.Attribute>();
                attrs.put(org.bouncycastle.asn1.cms.CMSAttributes.signingTime,new org.bouncycastle.asn1.cms.Attribute(
                    org.bouncycastle.asn1.cms.CMSAttributes.signingTime,new DERSet(new org.bouncycastle.asn1.cms.Time(date(when)))));
                var info=new JcaSignerInfoGeneratorBuilder(provider).setSignedAttributeGenerator(
                    new DefaultSignedAttributeTableGenerator(new org.bouncycastle.asn1.cms.AttributeTable(attrs)))
                    .build(new JcaContentSignerBuilder("SHA256withRSA").build(identity.key.getPrivate()),identity.cert);
                var generator=new TimeStampTokenGenerator(info,provider.get(new AlgorithmIdentifier(NISTObjectIdentifiers.id_sha256)),new ASN1ObjectIdentifier("1.2.3.4.5"));
                generator.setAccuracySeconds(1);
                generator.addCertificates(new CollectionStore<>(List.of(new JcaX509CertificateHolder(identity.cert),new JcaX509CertificateHolder(root.cert))));
                var request=new TimeStampRequestGenerator(); request.setCertReq(true);
                var token=generator.generate(request.generate(new ASN1ObjectIdentifier(algorithm.getOid()),digest),BigInteger.valueOf(date(when).getTime()),date(when));
                token.validate(new JcaSimpleSignerInfoVerifierBuilder().build(identity.cert));
                return new TimestampBinary(token.getEncoded());
            } catch(Exception ex) { throw new DSSException(ex); }
        };
    }
    static CommonCertificateVerifier verifier(Identity root, byte[] crl) {
        var trusted=new CommonTrustedCertificateSource(); trusted.addCertificate(new CertificateToken(root.cert));
        var verifier=Worker.offlineVerifier(trusted,new CommonCertificateSource());
        if(crl!=null) verifier.setCrlSource((target,issuer) -> {
            try { var token = new CRLToken(target,CRLUtils.buildCRLValidity(CRLUtils.buildCRLBinary(crl),issuer)); token.setExternalOrigin(RevocationOrigin.EXTERNAL); return token; }
            catch(Exception e) { throw new DSSException(e); }
        });
        // Fixture creation deliberately occurs in the past. These alerts only
        // affect augmentation, never Worker's validation policy.
        var silent=new SilentOnStatusAlert(); verifier.setAlertOnExpiredCertificate(silent);
        verifier.setAlertOnInvalidTimestamp(silent); verifier.setAlertOnMissingRevocationData(silent);
        verifier.setAlertOnUncoveredPOE(silent); verifier.setAlertOnNoRevocationAfterBestSignatureTime(silent);
        return verifier;
    }
    static CommonCertificateVerifier ocspVerifier(Identity root) {
        var verifier=verifier(root,null);
        verifier.setOcspSource((target,issuer) -> {
            try {
                var digests=new JcaDigestCalculatorProviderBuilder().build();
                var sha1=digests.get(new AlgorithmIdentifier(org.bouncycastle.asn1.oiw.OIWObjectIdentifiers.idSHA1));
                var builder=new org.bouncycastle.cert.ocsp.jcajce.JcaBasicOCSPRespBuilder(root.key.getPublic(),sha1);
                var id=new org.bouncycastle.cert.ocsp.CertificateID(sha1,new JcaX509CertificateHolder(issuer.getCertificate()),target.getSerialNumber());
                builder.addResponse(id,org.bouncycastle.cert.ocsp.CertificateStatus.GOOD,date("2024-01-04T00:00:00Z"),date("2030-01-01T00:00:00Z"),null);
                var basic=builder.build(new JcaContentSignerBuilder("SHA256withRSA").build(root.key.getPrivate()),
                    new X509CertificateHolder[]{new JcaX509CertificateHolder(root.cert)},date("2024-01-04T00:00:00Z"));
                var token=new eu.europa.esig.dss.spi.x509.revocation.ocsp.OCSPToken(basic,basic.getResponses()[0],target,issuer);
                token.setExternalOrigin(RevocationOrigin.EXTERNAL);return token;
            } catch(Exception e) {throw new DSSException(e);}
        });
        return verifier;
    }
    static SignatureValue sign(ToBeSigned bytes,Identity signer) throws Exception {
        var signature=Signature.getInstance("SHA256withRSA"); signature.initSign(signer.key.getPrivate()); signature.update(bytes.getBytes());
        return new SignatureValue(SignatureAlgorithm.RSA_SHA256,signature.sign());
    }
    @SuppressWarnings("unchecked") static Map<String,Object> row(Map<String,Object> result) { return ((List<Map<String,Object>>)result.get("signatures")).get(0); }
    static int passed;
    static void check(boolean value,String label) { if(!value) throw new AssertionError(label); passed++;System.out.println("PASS "+label); }
    public static void main(String[] args) throws Exception {
        Path folder=args.length==1 ? Path.of(args[0]) : Files.createTempDirectory("cie-ltv-tests-"); Files.createDirectories(folder);
        var root=identity("Root",1,null,true,false,"2045-01-01T00:00:00Z");
        var signer=identity("Signer expired today",2,root,false,false,"2025-01-01T00:00:00Z");
        var firstTsa=identity("Old TSA expired today",3,root,false,true,"2025-01-01T00:00:00Z");
        var renewedTsa=identity("Renewal TSA",4,root,false,true,"2032-01-01T00:00:00Z");
        var firstCrl=crl(root,"2024-01-02T01:00:00Z","2024-01-10T00:00:00Z",null);
        var newCrl=crl(root,"2024-01-04T00:00:00Z","2030-01-01T00:00:00Z",null);
        var verifier=verifier(root,firstCrl);
        byte[] input;
        try(var document=new PDDocument();var output=new ByteArrayOutputStream()) { document.addPage(new PDPage());document.save(output); input=output.toByteArray(); }
        var doc=new InMemoryDocument(input,"synthetic.pdf");
        var params=new PAdESSignatureParameters(); params.setSigningCertificate(new CertificateToken(signer.cert));
        params.setCertificateChain(new CertificateToken(signer.cert),new CertificateToken(root.cert)); params.bLevel().setSigningDate(date("2024-01-01T00:00:00Z"));
        params.setSignatureLevel(SignatureLevel.PAdES_BASELINE_T); params.setDigestAlgorithm(DigestAlgorithm.SHA256); params.setIncludeVRIDictionary(true);
        var service=new PAdESService(verifier); service.setTspSource(tsa(firstTsa,root,"2024-01-02T00:00:00Z"));
        var t=service.signDocument(doc,params,sign(service.getDataToSign(doc,params),signer));
        params.setSignatureLevel(SignatureLevel.PAdES_BASELINE_LTA); service.setTspSource(tsa(firstTsa,root,"2024-01-03T00:00:00Z"));
        var old=service.extendDocument(t,params); old.save(folder.resolve("old-lta.pdf").toString());
        var newerService=new PAdESService(verifier(root,newCrl)); newerService.setTspSource(tsa(renewedTsa,root,"2024-01-05T00:00:00Z"));
        var renewed=newerService.extendDocument(old,params); Path file=folder.resolve("renewed-lta.pdf"); renewed.save(file.toString());
        var result=Worker.validate(file,verifier(root,null),date("2026-10-16T12:00:00Z"));
        check(Boolean.TRUE.equals(result.get("allSignaturesLtaValid")),"renewed PAdES-LTA with expired original signer and TSA");
        check(((Number)result.get("dssDictionaryCount")).intValue()==2,"DSS revisions and VRI validation material extracted");
        check(((Number)row(result).get("archiveTimestampCount")).intValue()==2,"both PDF archival renewals identified");
        var untrusted=Worker.offlineVerifier(new CommonTrustedCertificateSource(),new CommonCertificateSource());
        check(!Boolean.TRUE.equals(Worker.validate(file,untrusted,date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"embedded roots never become trust anchors");
        Path tFile=folder.resolve("timestamp-only.pdf");t.save(tFile.toString());
        check(!Boolean.TRUE.equals(Worker.validate(tFile,verifier(root,null),date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"signature timestamp without DSS and archive is not LTA");
        check(!Boolean.TRUE.equals(Worker.validate(folder.resolve("old-lta.pdf"),verifier(root,null),date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"expired TSA without renewal cannot self-authenticate its old proof");
        check(Boolean.TRUE.equals(Worker.validate(folder.resolve("old-lta.pdf"),verifier(root,null),date("2024-01-06T00:00:00Z")).get("allSignaturesLtaValid")),"first LTA valid before TSA expiry");
        // Change a byte in the last RFC3161 token's signature, keeping ASN.1 valid.
        byte[] altered=Files.readAllBytes(file);
        try(var parsed=org.apache.pdfbox.Loader.loadPDF(altered)) {
            var stamps=parsed.getSignatureDictionaries();var last=stamps.get(stamps.size()-1);
            var token=new org.bouncycastle.cms.CMSSignedData(new ASN1InputStream(last.getContents(altered)).readObject().getEncoded());
            byte[] der=token.getEncoded();int atByte=last.getByteRange()[1]+1+2*(der.length-1);
            // PDF hex is case-insensitive: changing lowercase 'a' to 'A' would
            // leave the timestamp intact and randomly invalidate this test.
            int nibble=Character.digit((char)altered[atByte],16);
            if(nibble<0) throw new IllegalStateException("Timestamp signature is not hexadecimal");
            altered[atByte]=(byte)Character.forDigit(nibble ^ 1,16);
            if(java.util.Arrays.equals(last.getContents(Files.readAllBytes(file)),last.getContents(altered)))
                throw new IllegalStateException("Timestamp fixture mutation did not change the decoded token");
        }
        Path tampered=folder.resolve("tampered-last-archive.pdf");Files.write(tampered,altered);
        check(!Boolean.TRUE.equals(Worker.validate(tampered,verifier(root,null),date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"forged last archive timestamp cannot validate renewal chain");
        // Add a real unsigned PDF revision after a valid archive, not just whitespace.
        Path appended=folder.resolve("unsigned-page.pdf");
        try(var parsed=org.apache.pdfbox.Loader.loadPDF(file.toFile());var output=Files.newOutputStream(appended)) {
            parsed.addPage(new PDPage());parsed.getDocumentCatalog().getCOSObject().setNeedToBeUpdated(true);
            parsed.getPages().getCOSObject().setNeedToBeUpdated(true);parsed.saveIncremental(output);
        }
        check(!Boolean.TRUE.equals(Worker.validate(appended,verifier(root,null),date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"unsigned later page cannot inherit archival coverage");
        // Renewal data must not be accepted merely because a fresh DSS dictionary exists.
        Path injected=folder.resolve("unsigned-dss.pdf");
        try(var parsed=org.apache.pdfbox.Loader.loadPDF(folder.resolve("old-lta.pdf").toFile());var output=Files.newOutputStream(injected)) {
            var dict=parsed.getDocumentCatalog().getCOSObject();
            var dss=(org.apache.pdfbox.cos.COSDictionary)dict.getDictionaryObject(org.apache.pdfbox.cos.COSName.getPDFName("DSS"));
            var values=new org.apache.pdfbox.cos.COSArray();var stream=parsed.getDocument().createCOSStream();
            try(var out=stream.createOutputStream()){out.write(newCrl);}values.add(stream);
            dss.setItem(org.apache.pdfbox.cos.COSName.getPDFName("CRLs"),values);dss.setNeedToBeUpdated(true);dict.setNeedToBeUpdated(true);
            parsed.saveIncremental(output);
        }
        check(!Boolean.TRUE.equals(Worker.validate(injected,verifier(root,null),date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"DSS injected after old archive is not a renewal proof");
        // CAdES uses the same validator and archive-time-stamp-v3 processing.
        var cp=new CAdESSignatureParameters();cp.setSigningCertificate(new CertificateToken(signer.cert));
        cp.setCertificateChain(new CertificateToken(signer.cert),new CertificateToken(root.cert));cp.bLevel().setSigningDate(date("2024-01-01T00:00:00Z"));
        cp.setSignatureLevel(SignatureLevel.CAdES_BASELINE_T);cp.setSignaturePackaging(SignaturePackaging.ENVELOPING);cp.setDigestAlgorithm(DigestAlgorithm.SHA256);
        var cservice=new CAdESService(verifier(root,firstCrl));cservice.setTspSource(tsa(firstTsa,root,"2024-01-02T00:00:00Z"));
        var content=new InMemoryDocument("Synthetic CAdES archival fixture".getBytes(java.nio.charset.StandardCharsets.UTF_8),"fixture.txt");
        var ct=cservice.signDocument(content,cp,sign(cservice.getDataToSign(content,cp),signer));
        cp.setSignatureLevel(SignatureLevel.CAdES_BASELINE_LTA);cservice.setTspSource(tsa(firstTsa,root,"2024-01-03T00:00:00Z"));
        var clta=cservice.extendDocument(ct,cp);
        var cnew=new CAdESService(verifier(root,newCrl));cnew.setTspSource(tsa(renewedTsa,root,"2024-01-05T00:00:00Z"));
        Path p7m=folder.resolve("renewed-lta.p7m");cnew.extendDocument(clta,cp).save(p7m.toString());
        check(Boolean.TRUE.equals(Worker.validate(p7m,verifier(root,null),date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"CAdES-LTA archive-v3 renewal with expired original TSA");
        check(!Boolean.TRUE.equals(Worker.validate(p7m,untrusted,date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"CAdES embedded private root remains untrusted");
        var ocspService=new PAdESService(ocspVerifier(root));ocspService.setTspSource(tsa(renewedTsa,root,"2024-01-05T00:00:00Z"));
        Path ocspFile=folder.resolve("renewed-lta-ocsp.pdf");ocspService.extendDocument(old,params).save(ocspFile.toString());
        check(Boolean.TRUE.equals(Worker.validate(ocspFile,verifier(root,null),date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"archived OCSP responses support PDF renewal with expired TSA");
        var badVerifier=verifier(root,crl(root,"2023-12-31T00:00:00Z","2030-01-01T00:00:00Z",signer));
        badVerifier.setAlertOnRevokedCertificate(new SilentOnStatusAlert());
        var badService=new PAdESService(badVerifier);badService.setTspSource(tsa(renewedTsa,root,"2024-01-05T00:00:00Z"));
        Path revoked=folder.resolve("revoked-before-proof.pdf");badService.extendDocument(t,params).save(revoked.toString());
        check(!Boolean.TRUE.equals(Worker.validate(revoked,verifier(root,null),date("2026-10-16T12:00:00Z")).get("allSignaturesLtaValid")),"revocation before proof-of-existence cannot be repaired by archive timestamps");
        System.out.println("LTV_CASES_PASSED="+passed);
    }
}
