// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

import 'verification_date.dart';

String ltvStatusLabel(Object? status) => switch (status) {
  'passed' => 'Validazione LTA superata secondo la policy locale',
  'failed' => 'Validazione a lungo termine non superata',
  'no_archive_data' => 'Prove di archivio LTA assenti',
  _ => 'Validità a lungo termine non determinabile',
};
String historicalStatusLabel(Object? status) => switch (status) {
  'passed' => 'Validità storica verificata alla data della marca',
  'failed' => 'Validazione storica non superata',
  _ => 'Validità storica non determinabile',
};
String historicalReasonLabel(Object? reason) => switch (reason) {
  'revocation_reason_unknown' => 'Il motivo della revoca non è riconosciuto: le prove non consentono un esito storico positivo.',
  'crl_time_window_insufficient' => 'Le CRL disponibili non sono utilizzabili per questo riferimento temporale.',
  'trusted_timestamp_unavailable' =>
    'Manca una marca temporale verificata utilizzabile come riferimento.',
  'historical_certificate_status_verified' || 'validated_archival_proof' =>
    'Catene e prove di revoca verificate secondo la policy locale.',
  'certificate_revoked_at_reference_time' =>
    'Il certificato risultava revocato o non valido alla data di riferimento.',
  'revocation_history_ambiguous' => 'La storia della revoca non consente di stabilire la validità a quella data.',
  'document_signature_invalid' =>
    'L’integrità o la firma crittografica del documento non è valida.',
  _ => 'Le prove di fiducia o di revoca disponibili sono insufficienti per confermare la validità storica.',
};

class LongTermView extends StatelessWidget {
  const LongTermView({super.key, required this.result});
  final Map result;
  @override
  Widget build(BuildContext context) {
    final signatures = (result['signatures'] as List? ?? []).cast<Map>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, "Validazione storica e a lungo termine · DSS"),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (result['ok'] != true)
              Text(
                tr(
                  context,
                  "Controllo DSS non disponibile o non completato. Non è un esito positivo.",
                ),
              ),
            if (result['ok'] == true && signatures.isEmpty)
              Text(
                tr(
                  context,
                  "Nessuna firma validabile individuata dal motore DSS.",
                ),
              ),
            for (final (index, signature) in signatures.indexed) ...[
              const SizedBox(height: 10),
              Text(
                tr(context, "Firma {p0} · {p1}", [
                  index + 1,
                  signature['profile'] ??
                      tr(context, 'Profilo non determinato'),
                ]),
              ),
              Text(
                tr(
                  context,
                  historicalStatusLabel(signature['historicalStatus']),
                ),
              ),
              Text(
                tr(
                  context,
                  historicalReasonLabel(signature['historicalReason']),
                ),
              ),
              if ('${signature['historicalReferenceTime'] ?? ''}'.isNotEmpty)
                Text(
                  tr(context, "Data della marca verificata (UTC): {p0}", [
                    tr(
                      context,
                      verificationDate(signature['historicalReferenceTime']),
                    ),
                  ]),
                ),
              Text(tr(context, ltvStatusLabel(signature['longTermStatus']))),
              Text(
                tr(context, "Marche di archivio: {p0}", [
                  signature['archiveTimestampCount'] ?? 0,
                ]),
              ),
              if ('${signature['bestSignatureTime'] ?? ''}'.isNotEmpty)
                Text(
                  tr(context, "Riferimento valutato (UTC): {p0}", [
                    tr(
                      context,
                      verificationDate(signature['bestSignatureTime']),
                    ),
                  ]),
                ),
              Text(
                tr(context, "Diagnostica DSS: {p0} · {p1}", [
                  signature['indication'] ?? 'NOT_AVAILABLE',
                  signature['subIndication'] ?? 'NOT_AVAILABLE',
                ]),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              tr(
                context,
                "{p0}Elaborazione locale dei dati CMS/DSS/VRI e delle CRL recuperate: il documento non viene caricato online. Policy: CA CIE, PKI Difesa e radici pubbliche del runtime incluso. Il profilo LTA rilevato non garantisce un esito valido. Questo controllo non attesta la qualificazione eIDAS della firma.",
                [
                  result['crlRetrieval'] is Map &&
                          result['crlRetrieval']['enabled'] == true
                      ? tr(
                          context,
                          'Recupero CRL: {p0} scaricate; {p1} richieste non riuscite. ',
                          [
                            result['crlRetrieval']['downloaded'],
                            result['crlRetrieval']['failed'],
                          ],
                        )
                      : tr(
                          context,
                          'Recupero CRL non disponibile; uso dei soli dati incorporati. ',
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
