// SPDX-License-Identifier: BSD-3-Clause
package it.cieid.ltv;

import com.fasterxml.jackson.databind.ObjectMapper;
import eu.europa.esig.dss.diagnostic.SignatureWrapper;
import eu.europa.esig.dss.enumerations.Indication;
import eu.europa.esig.dss.enumerations.ValidationLevel;
import eu.europa.esig.dss.model.FileDocument;
import eu.europa.esig.dss.model.x509.CertificateToken;
import eu.europa.esig.dss.pades.validation.PDFDocumentValidator;
import eu.europa.esig.dss.spi.DSSUtils;
import eu.europa.esig.dss.spi.validation.CommonCertificateVerifier;
import eu.europa.esig.dss.spi.x509.CommonCertificateSource;
import eu.europa.esig.dss.spi.x509.CommonTrustedCertificateSource;
import eu.europa.esig.dss.validation.SignedDocumentValidator;
import eu.europa.esig.dss.validation.reports.Reports;
import java.nio.file.*;
import java.security.KeyStore;
import java.security.cert.X509Certificate;
import java.util.*;

/** Local DSS validation, with optional bounded CRL GETs. No document uploads. */
public final class Worker {
    private Worker() {}
    static CommonCertificateVerifier verifier(Path trust) throws Exception {
        var trusted = new CommonTrustedCertificateSource();
        var adjunct = new CommonCertificateSource();
        trusted.addCertificate(DSSUtils.loadCertificate(trust.resolve("root.pem").toFile()));
        for (String file : List.of("difesa-signing.pem", "difesa-tsa.pem"))
            trusted.addCertificate(DSSUtils.loadCertificate(trust.resolve(file).toFile()));
        for (String file : List.of("subca1.pem", "subca002.pem", "subca003.pem"))
            adjunct.addCertificate(DSSUtils.loadCertificate(trust.resolve(file).toFile()));
        var store = KeyStore.getInstance("JKS");
        try (var in = Files.newInputStream(trust.resolve("cacerts"))) { store.load(in, "changeit".toCharArray()); }
        for (var aliases = store.aliases(); aliases.hasMoreElements();) {
            var c = store.getCertificate(aliases.nextElement());
            if (c instanceof X509Certificate cert && cert.getBasicConstraints() >= 0)
                trusted.addCertificate(new CertificateToken(cert));
        }
        return offlineVerifier(trusted, adjunct);
    }
    static CommonCertificateVerifier offlineVerifier(CommonTrustedCertificateSource trusted, CommonCertificateSource adjunct) {
        // true prevents creation of the default HTTP AIA loader. OCSP/CRL sources
        // are null: DSS consumes embedded CMS/DSS/VRI material only.
        var verifier = new CommonCertificateVerifier(true);
        verifier.setTrustedCertSources(trusted);
        verifier.setAdjunctCertSources(adjunct);
        verifier.setAIASource(null); verifier.setOcspSource(null); verifier.setCrlSource(null);
        return verifier;
    }
    static String name(Object o) { return o == null ? "NOT_AVAILABLE" : o.toString(); }
    static String time(Date date) { return date == null ? "" : date.toInstant().toString(); }
    static Map<String,Object> validate(Path file, CommonCertificateVerifier verifier, Date now) throws Exception {
        return validate(file,verifier,now,null);
    }
    static Map<String,Object> validate(Path file, CommonCertificateVerifier verifier, Date now, CrlEvidence.Fetcher fetcher) throws Exception {
        long size = Files.size(file);
        if (size == 0 || size > 256L*1024*1024) throw new IllegalArgumentException("input_size");
        var validator = SignedDocumentValidator.fromDocument(new FileDocument(file.toFile()));
        validator.setCertificateVerifier(verifier);
        validator.setValidationTime(now);
        validator.setValidationLevel(ValidationLevel.ARCHIVAL_DATA);
        validator.setEnableEtsiValidationReport(false);
        var signaturePolicy = new eu.europa.esig.dss.spi.policy.SignaturePolicyProvider();
        signaturePolicy.setDataLoader(new eu.europa.esig.dss.spi.client.http.IgnoreDataLoader());
        validator.setSignaturePolicyProvider(signaturePolicy);
        validator.setSigningCertificateSource(new eu.europa.esig.dss.spi.x509.CommonX509URLCertificateSource(
            new eu.europa.esig.dss.spi.client.http.IgnoreDataLoader()));
        var evidence=new CrlEvidence(validator,verifier,now,fetcher);
        Reports reports = validator.validateDocument();
        var simple = reports.getSimpleReport();
        var detailed = reports.getDetailedReport();
        var diagnostic = reports.getDiagnosticData();
        if (simple.getSignatureIdList().size() > 128) throw new IllegalArgumentException("signature_limit");
        var signatures = new ArrayList<Map<String,Object>>();
        for (String id : simple.getSignatureIdList()) {
            SignatureWrapper signature = diagnostic.getSignatureById(id);
            var timestamps = new ArrayList<Map<String,Object>>();
            boolean latestArchivePassed = false;
            if(signature.getTimestampList().size()>128) throw new IllegalArgumentException("timestamp_limit");
            for (var ts : signature.getTimestampList()) {
                var row = new LinkedHashMap<String,Object>();
                row.put("type", name(ts.getType())); row.put("time", time(ts.getProductionTime()));
                row.put("imprintIntact", ts.isMessageImprintDataIntact());
                row.put("archivalIndication", name(detailed.getArchiveDataTimestampValidationIndication(ts.getId())));
                row.put("subIndication", name(detailed.getArchiveDataTimestampValidationSubIndication(ts.getId())));
                timestamps.add(row);
            }
            var archiveTimestamps = new ArrayList<>(signature.getArchiveTimestamps());
            archiveTimestamps.addAll(signature.getDocumentTimestamps());
            var latestArchive = archiveTimestamps.stream().max(Comparator.comparing(ts -> ts.getProductionTime())).orElse(null);
            if(latestArchive != null) latestArchivePassed = latestArchive.isMessageImprintDataIntact() &&
                detailed.getArchiveDataTimestampValidationIndication(latestArchive.getId()) == Indication.PASSED;
            int archives = archiveTimestamps.size();
            String profile = name(simple.getSignatureFormat(id));
            boolean archival = archives > 0 && profile.endsWith("BASELINE-LTA") && signature.isALevelTechnicallyValid();
            boolean currentRevisionCovered = true;
            if(latestArchive != null && latestArchive.getPDFRevision()!=null) {
                var range=latestArchive.getPDFRevision().getSignatureByteRange();
                currentRevisionCovered=range.size()==4 && range.get(2).longValue()+range.get(3).longValue()==size;
            }
            var revision=signature.getPDFRevision();
            boolean unexpectedPdfChanges=revision!=null && (!revision.getPdfUndefinedChanges().isEmpty() ||
                !revision.getPdfPageDifferenceConcernedPages().isEmpty() || !revision.getPdfVisualDifferenceConcernedPages().isEmpty() ||
                !revision.getPdfAnnotationsOverlapConcernedPages().isEmpty());
            boolean passed = currentRevisionCovered && !unexpectedPdfChanges && archival && latestArchivePassed && simple.getIndication(id)==Indication.TOTAL_PASSED &&
                detailed.getArchiveDataValidationIndication(id)==Indication.PASSED;
            boolean failed = simple.getIndication(id)==Indication.TOTAL_FAILED ||
                detailed.getArchiveDataValidationIndication(id)==Indication.FAILED;
            Date reference=simple.getBestSignatureTime(id);
            var history=CrlEvidence.Decision.unknown("trusted_timestamp_unavailable");
            boolean trustedTime=false;
            for(var ts:signature.getTimestampList()) {
                // A claimed signingTime or a bare TOTAL_PASSED cannot establish history.
                if(!name(ts.getType()).equals("SIGNATURE_TIMESTAMP") || !ts.isMessageImprintDataIntact() ||
                    detailed.getArchiveDataTimestampValidationIndication(ts.getId())!=Indication.PASSED ||
                    reference==null || !reference.equals(ts.getProductionTime())) continue;
                trustedTime=true;
                Long accuracy=evidence.timestampAccuracy.get(ts.getId());
                if(accuracy==null) { history=CrlEvidence.Decision.unknown("timestamp_accuracy_missing_or_unsupported");break; }
                var lower=new Date(reference.getTime()-accuracy);
                var upper=new Date(reference.getTime()+accuracy);
                var tsaStatus=evidence.path(ts,lower,upper,passed);
                var signerStatus=evidence.path(signature,lower,upper,passed);
                history=!tsaStatus.status().equals("passed") ? tsaStatus : signerStatus;
                if(signerStatus.reason().equals("revocation_reason_unknown")) history=signerStatus;
                // Validated archival POE can cover expired embedded revocation data,
                // including OCSP. Unknown reasons still override that DSS result.
                if(passed && Set.of("historical_revocation_evidence_missing","crl_time_window_insufficient",
                    "expired_certificate_revocation_history_missing").contains(history.reason()) && !evidence.incomplete)
                    history=new CrlEvidence.Decision("passed","validated_archival_proof");
                if(history.status().equals("passed") && simple.getIndication(id)!=Indication.TOTAL_PASSED)
                    history=CrlEvidence.Decision.unknown("dss_historical_validation_incomplete");
                break;
            }
            // Inspect accepted certificate paths even when DSS cannot establish a
            // timestamp; cached revocations must not hide an unsupported reason.
            var reasonCheck=evidence.path(signature,reference==null ? now : reference,passed);
            if(reasonCheck.reason().equals("revocation_reason_unknown")) history=reasonCheck;
            for(var ts:signature.getTimestampList()) {
                var check=evidence.path(ts,ts.getProductionTime(),passed);
                if(check.reason().equals("revocation_reason_unknown")) history=check;
            }
            if(history.reason().equals("revocation_reason_unknown") || evidence.incomplete) { passed=false;failed=false; }
            if(history.status().equals("failed")) { passed=false;failed=true; }
            if(simple.getIndication(id)==Indication.TOTAL_FAILED &&
                Set.of("SIG_CRYPTO_FAILURE","HASH_FAILURE").contains(name(simple.getSubIndication(id))))
                history=new CrlEvidence.Decision("failed","document_signature_invalid");
            var row = new LinkedHashMap<String,Object>();
            row.put("profile", profile); row.put("indication", name(simple.getIndication(id)));
            row.put("subIndication", name(simple.getSubIndication(id)));
            row.put("archiveIndication", name(detailed.getArchiveDataValidationIndication(id)));
            row.put("archiveSubIndication", name(detailed.getArchiveDataValidationSubIndication(id)));
            row.put("longTermStatus", passed ? "passed" : failed ? "failed" : archives==0 ? "no_archive_data" : "indeterminate");
            row.put("latestArchiveValidated",latestArchivePassed);
            row.put("currentRevisionCovered",currentRevisionCovered);
            row.put("unexpectedPdfChanges",unexpectedPdfChanges);
            row.put("reason",!currentRevisionCovered ? "unsigned_revision_after_latest_archive" : unexpectedPdfChanges ? "unexpected_pdf_changes" :
                passed ? "archival_validation_passed" : archives==0 ? "archive_proof_absent" : "archival_evidence_invalid_or_insufficient");
            row.put("bestSignatureTime", time(simple.getBestSignatureTime(id)));
            row.put("archiveTimestampCount", archives); row.put("timestamps", timestamps);
            row.put("historicalStatus",history.status()); row.put("historicalReason",history.reason());
            row.put("historicalReferenceTime",trustedTime ? time(reference) : "");
            signatures.add(row);
        }
        var result = new LinkedHashMap<String,Object>();
        result.put("ok", true); result.put("schema", 1); result.put("engine", "EU DSS 6.5.1");
        result.put("validationLevel", "ARCHIVAL_DATA"); result.put("offline", fetcher==null);
        result.put("historicalPolicy","authenticated_crl_v1"); result.put("crlRetrieval",evidence.summary());
        result.put("trustPolicy", "cie_difesa_and_pinned_temurin_roots");
        result.put("validationTime", time(now)); result.put("signatures", signatures);
        result.put("signatureCount", signatures.size());
        result.put("dssDictionaryCount", validator instanceof PDFDocumentValidator pdf ? pdf.getDssDictionaries().size() : 0);
        result.put("allSignaturesLtaValid", !signatures.isEmpty() && signatures.stream().allMatch(s -> "passed".equals(s.get("longTermStatus"))));
        return result;
    }
    public static void main(String[] args) {
        Map<String,Object> result;
        try {
            if(args.length!=2 && args.length!=3 && !(args.length==4 && args[3].equals("--network-stdin"))) throw new IllegalArgumentException("arguments");
            Path transport=args.length>=3 ? Path.of(args[2]).toAbsolutePath() : null;
            byte[] network=null;
            if(args.length==4){network=System.in.readNBytes(4097);if(network.length==0||network.length>4096)throw new IllegalArgumentException("network_config");}
            result=validate(Path.of(args[0]),verifier(Path.of(args[1])),new Date(),
                transport!=null && Files.isRegularFile(transport) ? CrlEvidence.transport(transport,network) : null);
            if(network!=null)java.util.Arrays.fill(network,(byte)0);
        } catch (Exception error) {
            result=Map.of("ok",false,"schema",1,"code","ltv_validation_failed","allSignaturesLtaValid",false);
        }
        try { System.out.println(new ObjectMapper().writeValueAsString(result)); }
        catch(Exception error) { System.exit(2); }
    }
}
