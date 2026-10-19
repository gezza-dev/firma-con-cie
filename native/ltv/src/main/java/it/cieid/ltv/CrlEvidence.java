// SPDX-License-Identifier: BSD-3-Clause
package it.cieid.ltv;

import eu.europa.esig.dss.crl.CRLUtils;
import eu.europa.esig.dss.diagnostic.AbstractTokenProxy;
import eu.europa.esig.dss.enumerations.RevocationOrigin;
import eu.europa.esig.dss.model.x509.CertificateToken;
import eu.europa.esig.dss.spi.validation.CommonCertificateVerifier;
import eu.europa.esig.dss.spi.x509.revocation.crl.CRLToken;
import eu.europa.esig.dss.validation.SignedDocumentValidator;
import java.io.*;
import java.net.URI;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import org.bouncycastle.asn1.*;
import org.bouncycastle.asn1.ocsp.BasicOCSPResponse;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.*;
import org.bouncycastle.cert.*;
import org.bouncycastle.cert.jcajce.JcaX509CertificateHolder;
import org.bouncycastle.cert.ocsp.*;
import org.bouncycastle.operator.jcajce.*;

/** Per-verification CRLs. No persistent cache, additional anchors, or document uploads. */
final class CrlEvidence {
    static final int MAX_BODY=24*1024*1024, MAX_TOTAL=64*1024*1024;
    interface Fetcher { byte[] get(String url, int milliseconds) throws Exception; }
    record Decision(String status, String reason) {
        static Decision unknown(String why) { return new Decision("indeterminate",why); }
        static Decision good() { return new Decision("passed","historical_certificate_status_verified"); }
    }
    final Map<String,CertificateToken> certificates=new LinkedHashMap<>();
    final Set<String> roots=new HashSet<>(), seen=new HashSet<>();
    final Map<String,byte[]> downloads=new HashMap<>();
    final List<X509CRLHolder> crls=new ArrayList<>();
    final List<BasicOCSPResp> ocsps=new ArrayList<>();
    final Map<String,Long> timestampAccuracy=new HashMap<>();
    final Map<X509CRLHolder,Map<String,Boolean>> authenticated=new IdentityHashMap<>();
    final Fetcher fetcher;
    final Date now;
    final long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(20);
    int attempts,downloaded,usable,bytes,failures;
    boolean incomplete;

    CrlEvidence(SignedDocumentValidator validator, CommonCertificateVerifier verifier, Date now, Fetcher fetcher) {
        this.now=now; this.fetcher=fetcher;
        for(var c:verifier.getTrustedCertSources().getCertificates()) { add(c); roots.add(c.getDSSIdAsString()); }
        for(var c:verifier.getAdjunctCertSources().getCertificates()) add(c);
        int signatures=0;
        for(var signature:validator.getSignatures()) {
            if(++signatures>128) throw new IllegalArgumentException("signature_limit");
            for(var c:signature.getCertificates()) add(c);
            for(var data:signature.getCompleteCRLSource().getAllRevocationBinaries()) addCrl(data.getBinaries());
            for(var data:signature.getCompleteOCSPSource().getAllRevocationBinaries()) addOcsp(data.getBinaries());
            if(signature.getAllTimestamps().size()>128) throw new IllegalArgumentException("timestamp_limit");
            for(var timestamp:signature.getAllTimestamps()) {
                try {
                    var accuracy=timestamp.getTimeStamp().getTimeStampInfo().getAccuracy();
                    if(accuracy!=null) {
                        long seconds=accuracy.getSeconds()==null ? 0 : accuracy.getSeconds().getValue().longValueExact();
                        long millis=accuracy.getMillis()==null ? 0 : accuracy.getMillis().getValue().longValueExact();
                        long micros=accuracy.getMicros()==null ? 0 : accuracy.getMicros().getValue().longValueExact();
                        if(seconds>=0 && seconds<=86400 && millis>=0 && millis<=999 && micros>=0 && micros<=999)
                            timestampAccuracy.put(timestamp.getDSSIdAsString(),seconds*1000+millis+(micros+999)/1000+1000);
                    }
                } catch(Exception ignored) { }
                for(var c:timestamp.getCertificates()) add(c);
                for(var data:timestamp.getCRLSource().getAllRevocationBinaries()) addCrl(data.getBinaries());
                for(var data:timestamp.getOCSPSource().getAllRevocationBinaries()) addOcsp(data.getBinaries());
            }
        }
        if(fetcher!=null) verifier.setCrlSource((target,issuer)->fetch(target,issuer));
    }
    void add(CertificateToken c) {
        if(certificates.size()>=2048) throw new IllegalArgumentException("certificate_limit");
        certificates.put(c.getDSSIdAsString(),c);
    }
    boolean reserve(byte[] data) {
        try {
            if(data==null || data.length==0 || data.length>MAX_BODY || bytes>MAX_TOTAL-data.length) { incomplete=true; return false; }
            String id=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
            if(!seen.add(id)) return false;
            if(seen.size()>64) { incomplete=true; return false; }
            bytes+=data.length;return true;
        } catch(Exception ex) { incomplete=true;return false; }
    }
    void addCrl(byte[] data) {
        if(reserve(data)) try { crls.add(new X509CRLHolder(CertificateList.getInstance(ASN1Primitive.fromByteArray(data)))); }
        catch(Exception ex) { incomplete=true; }
    }
    void addOcsp(byte[] data) {
        if(reserve(data)) try {
            Object response;
            try { response=new OCSPResp(data).getResponseObject(); }
            catch(Exception ex) { response=new BasicOCSPResp(BasicOCSPResponse.getInstance(ASN1Primitive.fromByteArray(data))); }
            if(response instanceof BasicOCSPResp basic) ocsps.add(basic);else incomplete=true;
        } catch(Exception ex) { incomplete=true; }
    }
    static boolean allowedUrl(String url) {
        try { var u=new URI(url);return url.length()<=2048 && u.getHost()!=null && u.getRawUserInfo()==null &&
            u.getFragment()==null && Set.of("http","https").contains(u.getScheme()); }
        catch(Exception ex) { return false; }
    }
    synchronized CRLToken fetch(CertificateToken target, CertificateToken issuer) {
        try {
            var encoded=target.getCertificate().getExtensionValue(Extension.cRLDistributionPoints.getId());
            if(encoded==null) return null;
            var points=CRLDistPoint.getInstance(ASN1Primitive.fromByteArray(ASN1OctetString.getInstance(encoded).getOctets()));
            for(var point:points.getDistributionPoints()) {
                if(point.getReasons()!=null || point.getCRLIssuer()!=null || point.getDistributionPoint()==null ||
                    point.getDistributionPoint().getType()!=DistributionPointName.FULL_NAME) continue;
                for(var name:GeneralNames.getInstance(point.getDistributionPoint().getName()).getNames()) {
                    if(name.getTagNo()!=GeneralName.uniformResourceIdentifier) continue;
                    String url=ASN1IA5String.getInstance(name.getName()).getString();
                    if(!allowedUrl(url)) continue;
                    byte[] data=downloads.get(url);
                    if(!downloads.containsKey(url)) {
                        long remaining=TimeUnit.NANOSECONDS.toMillis(deadline-System.nanoTime());
                        if(attempts>=8 || remaining<=0 || bytes>=MAX_TOTAL) { incomplete=true;return null; }
                        attempts++;
                        try { data=fetcher.get(url,(int)Math.min(6000,remaining)); }
                        catch(Exception ex) { failures++; }
                        downloads.put(url,data);
                        if(data!=null && data.length>0) { downloaded++;addCrl(data); }
                    }
                    if(data==null || data.length>MAX_BODY) continue;
                    var holder=new X509CRLHolder(data);
                    if(!authentic(holder,issuer) || !fresh(holder,now) || !complete(holder) ||
                        holder.getThisUpdate().before(target.getCertificate().getNotBefore())) continue;
                    var validity=CRLUtils.buildCRLValidity(CRLUtils.buildCRLBinary(data),issuer);
                    if(!validity.isSignatureIntact()) continue;
                    var token=new CRLToken(target,validity);token.setExternalOrigin(RevocationOrigin.EXTERNAL);usable++;
                    return token;
                }
            }
        } catch(Exception ex) { incomplete=true; }
        return null;
    }
    static boolean complete(X509CRLHolder crl) {
        if(crl.getExtension(Extension.deltaCRLIndicator)!=null || crl.getExtension(Extension.issuingDistributionPoint)!=null) return false;
        for(Object oid:crl.getCriticalExtensionOIDs()) if(!Set.of(Extension.authorityKeyIdentifier,Extension.cRLNumber).contains(oid)) return false;
        return true;
    }
    boolean authentic(X509CRLHolder crl, CertificateToken issuer) {
        return authenticated.computeIfAbsent(crl,ignored->new HashMap<>()).computeIfAbsent(issuer.getDSSIdAsString(),ignored->{
            try {
                var cert=issuer.getCertificate();var usage=cert.getKeyUsage();
                return crl.getIssuer().equals(X500Name.getInstance(cert.getSubjectX500Principal().getEncoded())) &&
                    cert.getBasicConstraints()>=0 && usage!=null && usage.length>6 && usage[6] &&
                    Set.of("1.2.840.113549.1.1.11","1.2.840.113549.1.1.12","1.2.840.113549.1.1.13",
                        "1.2.840.10045.4.3.2","1.2.840.10045.4.3.3","1.2.840.10045.4.3.4").contains(crl.toASN1Structure().getSignatureAlgorithm().getAlgorithm().getId()) &&
                    cert.getNotBefore().compareTo(crl.getThisUpdate())<=0 && cert.getNotAfter().compareTo(crl.getThisUpdate())>=0 &&
                    crl.isSignatureValid(new JcaContentVerifierProviderBuilder().build(issuer.getPublicKey()));
            } catch(Exception ex) { return false; }
        });
    }
    static boolean fresh(X509CRLHolder crl,Date at) {
        return crl.getNextUpdate()!=null && crl.getNextUpdate().after(crl.getThisUpdate()) &&
            !crl.getThisUpdate().after(at) && !crl.getNextUpdate().before(at);
    }
    CertificateToken issuer(CertificateToken target) {
        for(var c:certificates.values()) try {
            if(!target.equals(c) && target.getCertificate().getIssuerX500Principal().equals(c.getCertificate().getSubjectX500Principal())) {
                target.getCertificate().verify(c.getPublicKey());return c;
            }
        } catch(Exception ignored) { }
        return null;
    }
    static int reason(X509CRLEntryHolder entry) {
        var ext=entry.getExtension(Extension.reasonCode);
        return ext==null ? 0 : ASN1Enumerated.getInstance(ext.getParsedValue()).intValueExact();
    }
    static boolean known(int reason) { return Set.of(0,1,2,3,4,5,6,8,9,10).contains(reason); }
    boolean unknownOcspReason(CertificateToken target,CertificateToken issuer) throws Exception {
        for(var response:ocsps) for(var one:response.getResponses()) {
            if(!one.getCertID().getSerialNumber().equals(target.getSerialNumber()) ||
                !one.getCertID().matchesIssuer(new JcaX509CertificateHolder(issuer.getCertificate()),new JcaDigestCalculatorProviderBuilder().build()) ||
                !(one.getCertStatus() instanceof RevokedStatus revoked) || !revoked.hasRevocationReason() || known(revoked.getRevocationReason())) continue;
            if(response.isSignatureValid(new JcaContentVerifierProviderBuilder().build(issuer.getPublicKey()))) return true;
            for(var responder:response.getCerts()) {
                var eku=responder.getExtension(Extension.extendedKeyUsage);
                if(responder.getIssuer().equals(X500Name.getInstance(issuer.getCertificate().getSubjectX500Principal().getEncoded())) &&
                    responder.isValidOn(response.getProducedAt()) && eku!=null && ExtendedKeyUsage.getInstance(eku.getParsedValue()).hasKeyPurposeId(KeyPurposeId.id_kp_OCSPSigning) &&
                    responder.isSignatureValid(new JcaContentVerifierProviderBuilder().build(issuer.getPublicKey())) &&
                    response.isSignatureValid(new JcaContentVerifierProviderBuilder().build(responder))) return true;
            }
        }
        return false;
    }
    Decision certificate(CertificateToken target,Date reference,boolean archived) {
        return certificate(target,reference,reference,archived);
    }
    Decision certificate(CertificateToken target,Date lower,Date reference,boolean archived) {
        if(roots.contains(target.getDSSIdAsString())) return Decision.good();
        var issuer=issuer(target);if(issuer==null) return Decision.unknown("historical_chain_incomplete");
        boolean good=false;String missing="historical_revocation_evidence_missing";
        try {
            if(unknownOcspReason(target,issuer)) return Decision.unknown("revocation_reason_unknown");
            for(var crl:crls) {
                if(!authentic(crl,issuer)) continue;
                var entry=crl.getRevokedCertificate(target.getSerialNumber());
                if(entry!=null && !known(reason(entry))) return Decision.unknown("revocation_reason_unknown");
                if(!complete(crl)) { missing="crl_scope_unsupported";continue; }
                if(crl.getThisUpdate().before(reference) || crl.getThisUpdate().before(target.getCertificate().getNotBefore()) ||
                    crl.getThisUpdate().after(now) || (!archived && !fresh(crl,now))) { missing="crl_time_window_insufficient";continue; }
                if(crl.getThisUpdate().after(target.getCertificate().getNotAfter())) {
                    var retained=crl.getExtension(new ASN1ObjectIdentifier("2.5.29.60"));
                    if(retained==null || ASN1GeneralizedTime.getInstance(retained.getParsedValue()).getDate().after(target.getCertificate().getNotAfter())) {
                        missing="expired_certificate_revocation_history_missing";continue;
                    }
                }
                if(target.getCertificate().getNotBefore().after(lower) || target.getCertificate().getNotAfter().before(reference))
                    return Decision.unknown("certificate_does_not_cover_timestamp_accuracy");
                if(entry==null) { good=true;continue; }
                if(!entry.getCriticalExtensionOIDs().isEmpty()) return Decision.unknown("crl_entry_extension_unsupported");
                Date revoked=entry.getRevocationDate();
                if(revoked.after(crl.getThisUpdate())) return Decision.unknown("revocation_time_invalid");
                var invalidity=entry.getExtension(Extension.invalidityDate);
                Date invalid=invalidity==null ? revoked : ASN1GeneralizedTime.getInstance(invalidity.getParsedValue()).getDate();
                if(invalid.after(revoked)) return Decision.unknown("revocation_time_invalid");
                int why=reason(entry);
                if(why==0) return Decision.unknown("revocation_history_ambiguous");
                if(!invalid.after(lower) || !revoked.after(lower)) return new Decision("failed","certificate_revoked_at_reference_time");
                if(!invalid.after(reference) || !revoked.after(reference)) return Decision.unknown("revocation_within_timestamp_accuracy");
                if(why==6 || why==8 || ((why==1 || why==2 || why==10) && invalidity==null))
                    return Decision.unknown("revocation_history_ambiguous");
                good=true;
            }
        } catch(Exception ex) { return Decision.unknown("revocation_evidence_malformed"); }
        return good ? Decision.good() : Decision.unknown(missing);
    }
    Decision path(AbstractTokenProxy token,Date reference,boolean archived) {
        return path(token,reference,reference,archived);
    }
    Decision path(AbstractTokenProxy token,Date lower,Date reference,boolean archived) {
        var chain=new LinkedHashMap<String,CertificateToken>();
        if(token.getSigningCertificate()==null) return Decision.unknown("historical_chain_incomplete");
        var wrappers=new ArrayList<>(token.getCertificateChain());wrappers.add(token.getSigningCertificate());
        for(var c:wrappers) {
            var encoded=certificates.get(c.getId());if(encoded==null) return Decision.unknown("historical_chain_incomplete");
            chain.put(c.getId(),encoded);
        }
        Decision result=Decision.good();
        for(var cert:chain.values()) {
            var row=certificate(cert,lower,reference,archived);
            if(row.reason().equals("revocation_reason_unknown")) return row;
            if(!row.status().equals("passed")) result=row;
        }
        return incomplete ? Decision.unknown("revocation_evidence_limits_or_malformed") : result;
    }
    Map<String,Object> summary() { return Map.of("enabled",fetcher!=null,"attempted",attempts,"downloaded",downloaded,
        "usable",usable,"failed",failures,"budgetExhausted",attempts>=8 || System.nanoTime()>=deadline,"persistentCache",false); }

    static Fetcher transport(Path executable) { return transport(executable,null); }
    static Fetcher transport(Path executable,byte[] network) {
        return (url,milliseconds)->{
            var command=new ArrayList<String>(List.of(executable.toString(),url,Integer.toString(milliseconds)));
            if(network!=null)command.add("--network-stdin");
            var builder=new ProcessBuilder(command);
            builder.environment().keySet().removeIf(k->!Set.of("SYSTEMROOT","WINDIR","TEMP","TMP","HOME","LANG","LC_ALL").contains(k.toUpperCase(Locale.ROOT)));
            builder.redirectError(ProcessBuilder.Redirect.DISCARD);
            var process=builder.start();
            try(var pipe=process.getOutputStream()){if(network!=null)pipe.write(network);}
            catch(Exception error){process.destroyForcibly();throw new IOException("crl_config_pipe");}
            try(var executor=Executors.newVirtualThreadPerTaskExecutor()) {
                var result=executor.submit(()->{
                    try(var input=process.getInputStream();var output=new ByteArrayOutputStream()) {
                        byte[] buffer=new byte[65536];int n;
                        while((n=input.read(buffer))!=-1) { if(output.size()>MAX_BODY-n) throw new IOException("crl_size");output.write(buffer,0,n); }
                        return output.toByteArray();
                    }
                });
                try {
                    byte[] bytes=result.get(milliseconds+1500L,TimeUnit.MILLISECONDS);
                    if(!process.waitFor(1000,TimeUnit.MILLISECONDS) || process.exitValue()!=0) throw new IOException("crl_fetch_failed");
                    return bytes;
                } finally { process.destroyForcibly();result.cancel(true); }
            }
        };
    }
}
