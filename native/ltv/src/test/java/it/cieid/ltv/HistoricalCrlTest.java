// SPDX-License-Identifier: BSD-3-Clause
package it.cieid.ltv;

import eu.europa.esig.dss.cades.*;
import eu.europa.esig.dss.cades.signature.CAdESService;
import eu.europa.esig.dss.enumerations.*;
import eu.europa.esig.dss.model.*;
import eu.europa.esig.dss.model.x509.CertificateToken;
import java.nio.file.*;
import java.util.*;
import org.bouncycastle.asn1.*;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.*;
import org.bouncycastle.cert.*;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.junit.jupiter.api.Test;
import static it.cieid.ltv.LtvSelfTest.*;

/** Shared deterministic tests, with no card, real identities, network or OS trust changes. */
public final class HistoricalCrlTest {
    static byte[] evidence(Identity root,Identity revoked,int reason,String revokedAt,String from,String until,
        boolean retention,String invalidity,boolean scoped) throws Exception {
        var builder=new X509v2CRLBuilder(X500Name.getInstance(root.cert().getSubjectX500Principal().getEncoded()),date(from));
        builder.setNextUpdate(date(until));
        if(retention) builder.addExtension(new ASN1ObjectIdentifier("2.5.29.60"),false,new ASN1GeneralizedTime(date("2023-01-01T00:00:00Z")));
        if(scoped) builder.addExtension(Extension.issuingDistributionPoint,true,new IssuingDistributionPoint(null,true,false,null,false,false));
        if(revoked!=null) {
            var extensions=new ExtensionsGenerator();extensions.addExtension(Extension.reasonCode,false,new ASN1Enumerated(reason));
            if(invalidity!=null) extensions.addExtension(Extension.invalidityDate,false,new ASN1GeneralizedTime(date(invalidity)));
            builder.addCRLEntry(revoked.cert().getSerialNumber(),date(revokedAt),extensions.generate());
        }
        return builder.build(new JcaContentSignerBuilder("SHA256withRSA").build(root.key().getPrivate())).getEncoded();
    }
    static Path signed(Path dir,Identity signer,Identity root,Identity clock) throws Exception {
        var p=new CAdESSignatureParameters();p.setSigningCertificate(new CertificateToken(signer.cert()));
        p.setCertificateChain(new CertificateToken(signer.cert()),new CertificateToken(root.cert()));
        p.setSignatureLevel(SignatureLevel.CAdES_BASELINE_T);p.setSignaturePackaging(SignaturePackaging.ENVELOPING);
        p.setDigestAlgorithm(DigestAlgorithm.SHA256);p.bLevel().setSigningDate(date("2024-01-01T00:00:00Z"));
        var service=new CAdESService(verifier(root,null));service.setTspSource(tsa(clock,root,"2024-01-02T00:00:00Z"));
        var content=new InMemoryDocument("Historical evidence fixture".getBytes(java.nio.charset.StandardCharsets.UTF_8),"fixture.txt");
        var out=dir.resolve("fixture-"+signer.cert().getSerialNumber()+".p7m");
        service.signDocument(content,p,sign(service.getDataToSign(content,p),signer)).save(out.toString());return out;
    }
    static void expect(Path doc,Identity root,CrlEvidence.Fetcher fetcher,String status,String label) throws Exception {
        var before=Files.readAllBytes(doc);
        var result=Worker.validate(doc,verifier(root,null),date("2026-10-16T12:00:00Z"),fetcher);
        var signature=row(result);
        if(!status.equals(signature.get("historicalStatus"))) throw new AssertionError(label+": "+signature.get("historicalStatus")+" / "+signature.get("historicalReason"));
        if(Boolean.TRUE.equals(result.get("allSignaturesLtaValid"))) throw new AssertionError("T is not LTA");
        if(!Arrays.equals(before,Files.readAllBytes(doc))) throw new AssertionError("original changed");
        System.out.println("PASS "+label);
    }
    public static void main(String[] args) throws Exception {
        Path dir=Files.createTempDirectory("cie-history-tests-");
        try {
            String url="https://crl.test.invalid/full.crl";
            var root=identity("History root",51,null,true,false,"2045-01-01T00:00:00Z");
            var signer=identity("History signer",52,root,false,false,"2035-01-01T00:00:00Z",url);
            var clock=identity("History TSA",53,root,false,true,"2035-01-01T00:00:00Z",url);
            var expired=identity("Expired history signer",54,root,false,false,"2025-01-01T00:00:00Z",url);
            var other=identity("Wrong history issuer",55,null,true,false,"2045-01-01T00:00:00Z");
            var doc=signed(dir,signer,root,clock);var oldDoc=signed(dir,expired,root,clock);
            String from="2026-10-16T11:00:00Z",until="2026-10-23T11:00:00Z",later="2025-01-01T00:00:00Z";
            var good=evidence(root,null,0,null,from,until,false,null,false);
            expect(doc,root,(u,t)->good,"passed","fresh authentic CRL validates historical CAdES-T without claiming LTA");
            expect(doc,root,null,"indeterminate","missing external and embedded evidence remains indeterminate");
            expect(doc,root,(u,t)->{throw new java.io.IOException("offline");},"indeterminate","network failure is not historical validity");
            var unknown=evidence(root,signer,7,later,from,until,false,null,false);
            expect(doc,root,(u,t)->unknown,"indeterminate","unknown revocation reason overrides raw DSS success and cache reuse");
            var unknownTsa=evidence(root,clock,7,later,from,until,false,null,false);
            expect(doc,root,(u,t)->unknownTsa,"indeterminate","unknown TSA revocation reason is indeterminate");
            var superseded=evidence(root,signer,4,later,from,until,false,null,false);
            expect(doc,root,(u,t)->superseded,"passed","recognized revocation after trusted timestamp preserves historical validity");
            var compromised=evidence(root,signer,1,later,from,until,false,null,false);
            expect(doc,root,(u,t)->compromised,"indeterminate","compromise without effective date does not authorize backdating");
            var revoked=evidence(root,signer,4,"2023-12-31T00:00:00Z",from,until,false,null,false);
            expect(doc,root,(u,t)->revoked,"failed","revocation before trusted reference fails historical validation");
            var overlap=evidence(root,signer,4,"2024-01-02T00:00:01Z",from,until,false,null,false);
            expect(doc,root,(u,t)->overlap,"indeterminate","revocation overlapping timestamp accuracy is indeterminate");
            var stale=evidence(root,null,0,null,"2023-12-31T00:00:00Z","2030-01-01T00:00:00Z",false,null,false);
            expect(doc,root,(u,t)->stale,"indeterminate","CRL predating timestamp is not sufficient historical evidence");
            var past=evidence(root,null,0,null,"2024-01-03T00:00:00Z","2024-01-10T00:00:00Z",false,null,false);
            expect(doc,root,(u,t)->past,"indeterminate","expired external CRL without archival POE cannot validate history");
            var corrupt=good.clone();corrupt[corrupt.length-1]^=1;
            expect(doc,root,(u,t)->corrupt,"indeterminate","forged CRL signature is rejected");
            var wrong=evidence(other,null,0,null,from,until,false,null,false);
            expect(doc,root,(u,t)->wrong,"indeterminate","unrelated CRL issuer cannot supply status");
            expect(oldDoc,root,(u,t)->good,"indeterminate","expired certificate needs authenticated retention information");
            var retained=evidence(root,null,0,null,from,until,true,null,false);
            expect(oldDoc,root,(u,t)->retained,"passed","retained expired certificate status supports historical validation");
            var invalidity=evidence(root,signer,4,later,from,until,false,"2023-12-31T00:00:00Z",false);
            expect(doc,root,(u,t)->invalidity,"failed","authenticated invalidity before timestamp is not hidden by later revocation");
            var scoped=evidence(root,null,0,null,from,until,false,null,true);
            expect(doc,root,(u,t)->scoped,"indeterminate","scoped CRL cannot stand in for a complete CRL");
            var trailing=Arrays.copyOf(good,good.length+1);
            expect(doc,root,(u,t)->trailing,"indeterminate","trailing CRL bytes are rejected");
            for(String bad:List.of("file:///etc/passwd","https://user:secret@example.com/a","ftp://example.com/a","http://example.com/a#fragment"))
                if(CrlEvidence.allowedUrl(bad)) throw new AssertionError("unsafe URL accepted");
            System.out.println("PASS external CRL protocol and credential restrictions");
        } finally { try(var paths=Files.walk(dir)) { for(var p:paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(p); } }
    }
    @Test void historicalEvidencePolicy() throws Exception { main(new String[0]); }
}
