// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'app_notification.dart';

import 'package:flutter/material.dart';

import 'native_bridge.dart';
import 'long_term_view.dart';
import 'verification_date.dart';

String revocationLabel(Object? value) => switch (value) {
  0 => 'Non revocato secondo il servizio consultato',
  1 => 'Certificato revocato',
  2 => 'Certificato sospeso',
  4 => 'Informazioni di revoca non caricate',
  _ => 'Stato di revoca non determinato',
};

String trustChainLabel(Map signer) => switch (signer['trustChainStatus']) {
  'trusted' =>
    signer['trustSource'] == 'cie_ministry'
        ? 'Catena di fiducia verificata · CA ministeriale CIE'
        : signer['trustSource'] == 'difesa_ministry'
        ? 'Catena di fiducia verificata · PKI Ministero della Difesa'
        : 'Catena di fiducia verificata · archivio del sistema',
  'untrusted' => 'Catena non attendibile · autorità non riconosciuta',
  'invalid' => 'Catena di certificati non valida',
  'unknown' => 'Catena di fiducia non determinabile',
  _ => 'Catena di fiducia non verificata dal backend',
};

String timestampLabel(Object? status) => switch (status) {
  'verified' => 'Impronta, firma e catena TSA verificate',
  'absent' => 'Nessuna marca temporale della firma',
  'invalid' => 'Marca temporale non valida',
  'indeterminate' =>
    'Marca temporale non verificabile con le prove disponibili',
  _ => 'Verifica della marca temporale non disponibile',
};
String timestampDetail(Object? reason) => switch (reason) {
  'tsa_chain_not_trusted_at_timestamp' => 'La catena di fiducia della TSA non è ricostruibile o attendibile alla data della marca.',
  'timestamp_critical_extension_unsupported' =>
    'La marca contiene un’estensione critica non supportata dal verificatore.',
  'timestamp_extension_limit' =>
    'La marca supera il limite di estensioni supportate dal verificatore.',
  'timestamp_version_unsupported' =>
    'La versione della marca non è supportata dal verificatore.',
  'timestamp_algorithm_unsupported' ||
  'timestamp_signature_algorithm_unsupported' =>
    'L’algoritmo della marca non è supportato dalla policy del verificatore.',
  'timestamp_malformed' => 'La struttura della marca temporale è malformata.',
  'timestamp_duplicate_extension' =>
    'La marca contiene estensioni duplicate e non può essere accettata.',
  _ => '',
};
String historicalLabel(Map signer) => switch (signer['historicalStatus']) {
  'valid_at_timestamp' =>
    'Valida alla data della marca secondo le prove verificate',
  'invalid_at_timestamp' =>
    'Non valida secondo i controlli alla data della marca',
  _ => 'Validità storica non determinabile con le prove disponibili',
};
String historicalDetail(Object? reason) => switch (reason) {
  'trusted_time_unavailable' => 'Manca una marca temporale attendibile.',
  'tsa_current_status_missing_requires_archive_renewal_proof' => 'Lo stato attuale della TSA non è accertato; occorre una prova di rinnovo archivistico.',
  'timestamp_accuracy_missing_or_unsupported' =>
    'La precisione della marca non è dichiarata o non è supportata.',
  'tsa_historical_revocation_evidence_missing_or_adverse' =>
    'Le prove storiche di revoca della TSA mancano o segnalano un problema.',
  'signer_historical_chain_or_revocation_evidence_missing' =>
    'Mancano la catena o le prove storiche di revoca del firmatario.',
  _ => '',
};

enum CheckOutcome { positive, negative, indeterminate }

CheckOutcome booleanOutcome(Object? value) => value == true
    ? CheckOutcome.positive
    : value == false
    ? CheckOutcome.negative
    : CheckOutcome.indeterminate;

CheckOutcome certificateOutcome(Map signer) {
  if (signer['certificateWithinValidity'] == false ||
      const ['untrusted', 'invalid'].contains(signer['trustChainStatus'])) {
    return CheckOutcome.negative;
  }
  if (signer['certificateWithinValidity'] == true &&
      signer['trustChainValidated'] == true &&
      signer['trustChainStatus'] == 'trusted') {
    return CheckOutcome.positive;
  }
  return CheckOutcome.indeterminate;
}

CheckOutcome revocationOutcome(Map signer) {
  if (const [1, 2].contains(signer['revocationStatus']) ||
      const [1, 2].contains(signer['chainRevocationStatus'])) {
    return CheckOutcome.negative;
  }
  if (signer['revocationStatus'] == 0 && signer['chainRevocationStatus'] == 0) {
    return CheckOutcome.positive;
  }
  return CheckOutcome.indeterminate;
}

String certificateSummary(Map signer) {
  if (signer['certificateWithinValidity'] == false) {
    return 'Fuori dal periodo di validità attuale';
  }
  if (const ['untrusted', 'invalid'].contains(signer['trustChainStatus'])) {
    return trustChainLabel(signer);
  }
  return certificateOutcome(signer) == CheckOutcome.positive
      ? 'Periodo di validità e catena verificati'
      : 'Verifica del certificato non conclusa';
}

String revocationSummary(Map signer) {
  if (const [1, 2].contains(signer['revocationStatus'])) {
    return revocationLabel(signer['revocationStatus']);
  }
  if (const [1, 2].contains(signer['chainRevocationStatus'])) {
    return 'Un certificato della catena risulta revocato o sospeso';
  }
  if (signer['revocationStatus'] == 0 && signer['chainRevocationStatus'] != 0) {
    return 'Firmatario non revocato; revoca della catena non determinata';
  }
  return revocationOutcome(signer) == CheckOutcome.positive
      ? 'Non revocato secondo le prove consultate'
      : 'Stato di revoca non determinato';
}

class VerificationView extends StatelessWidget {
  const VerificationView({super.key, required this.result});
  final JsonResult result;
  @override
  Widget build(BuildContext context) {
    if (result['ok'] != true) return VerificationProblem(result: result);
    final signers = (result['signers'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final ltv = result['ltv'] is Map ? result['ltv'] as Map : null;
    final archival = ltv?['ok'] == true
        ? (ltv?['signatures'] as List? ?? []).whereType<Map>().toList()
        : <Map>[];
    final fallback = result['nativeVerification'] is Map;
    final count = signers.isNotEmpty ? signers.length : archival.length;
    if (count == 0 && result['signatureCount'] == 0 && !fallback) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(tr(context, "Nessuna firma trovata")),
      );
    }
    if (count == 0) {
      return VerificationProblem(
        result: {'ok': false, 'code': 'verification_incomplete'},
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, "Numero di sottoscrittori: {p0}", [count]),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (fallback)
          Text(
            tr(
              context,
              "Verifica nativa non completata. Sono disponibili gli esiti separati dell’analisi storica DSS.",
            ),
          ),
        if (signers.isNotEmpty && result['signatureCount'] != signers.length)
          Text(
            tr(
              context,
              "Verifica non completata per tutti i firmatari. Consulta i dettagli disponibili.",
            ),
          ),
        for (final (index, signer) in signers.indexed)
          _SignerCard(
            key: ValueKey('native-$index'),
            signer: signer,
            index: index,
          ),
        if (signers.isEmpty)
          for (final (index, signature) in archival.indexed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        context,
                        "Firmatario {p0} · identità non disponibile",
                        [index + 1],
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      tr(
                        context,
                        "Firma e certificato: verifica nativa non completata",
                      ),
                    ),
                    Text(
                      tr(
                        context,
                        historicalStatusLabel(signature['historicalStatus']),
                      ),
                    ),
                    Text(
                      tr(context, ltvStatusLabel(signature['longTermStatus'])),
                    ),
                  ],
                ),
              ),
            ),
        if (ltv != null)
          ExpansionTile(
            title: Text(tr(context, "Validità storica e a lungo termine")),
            subtitle: Text(
              ltv['ok'] != true
                  ? tr(context, "Controllo non completato")
                  : archival.isEmpty
                  ? tr(context, "Nessuna prova di firma disponibile")
                  : tr(context, "Analisi DSS separata · {p0} {p1}", [
                      archival.length,
                      tr(context, archival.length == 1 ? 'firma' : 'firme'),
                    ]),
            ),
            children: [
              if (signers.isNotEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    tr(
                      context,
                      "Gli esiti DSS sono riportati nell’ordine del relativo motore. Non vengono associati ai firmatari sopra sulla sola base della posizione nell’elenco.",
                    ),
                  ),
                ),
              LongTermView(result: ltv),
            ],
          ),
        if ((result['documentTimestampCount'] as num? ?? 0) > 0)
          ExpansionTile(
            title: Text(tr(context, "Marche temporali del documento")),
            subtitle: Text(
              tr(context, timestampLabel(result['documentTimestampStatus'])),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr(
                    context,
                    "Marche del documento PDF: {p0}. La marca del documento non determina da sola la validità storica delle firme.",
                    [result['documentTimestampCount']],
                  ),
                ),
              ),
              if ('${result['documentTimestampTime'] ?? ''}'.isNotEmpty)
                Text(
                  tr(context, "Data della marca (UTC): {p0}", [
                    tr(
                      context,
                      verificationDate(result['documentTimestampTime']),
                    ),
                  ]),
                ),
              Text(
                tr(context, timestampDetail(result['documentTimestampReason'])),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          tr(
            context,
            "Firma integra, certificato attendibile e stato di revoca sono controlli distinti. Un esito non determinato richiede ulteriori prove.",
          ),
        ),
        ExpansionTile(
          title: Text(tr(context, "Come leggere i risultati")),
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                tr(
                  context,
                  "I controlli attuali sono separati dalla validità alla data di una marca temporale. La data dichiarata dal firmatario non prova quando il documento è stato firmato. Questa applicazione non certifica la qualificazione o il valore legale della firma.",
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignerCard extends StatelessWidget {
  const _SignerCard({super.key, required this.signer, required this.index});
  final Map signer;
  final int index;
  @override
  Widget build(BuildContext context) {
    final commonName = '${signer['commonName'] ?? ''}'.trim();
    // Use this signer's certificate, never the inserted or previously paired CIE.
    final fullName = [signer['name'], signer['surname']]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    final name = fullName.isEmpty
        ? commonName
        : commonName.isEmpty ||
              commonName.toUpperCase() == fullName.toUpperCase()
        ? fullName
        : '$fullName\n$commonName';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              name.isEmpty
                  ? tr(context, "Firmatario {p0} · nome non disponibile", [
                      index + 1,
                    ])
                  : name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _CheckRow(
              'Firma',
              signer['signatureValid'] == true
                  ? 'Integra'
                  : signer['signatureValid'] == false
                  ? 'Non integra'
                  : 'Integrità non determinata',
              booleanOutcome(signer['signatureValid']),
            ),
            _CheckRow(
              'Certificato',
              certificateSummary(signer),
              certificateOutcome(signer),
            ),
            _CheckRow(
              'Revoca',
              revocationSummary(signer),
              revocationOutcome(signer),
            ),
            if (signer['timestampStatus'] == 'verified' &&
                '${signer['timestampTime'] ?? ''}'.isNotEmpty)
              Text(
                tr(context, "Marca temporale verificata: {p0}", [
                  tr(context, verificationDate(signer['timestampTime'])),
                ]),
              ),
            if (const [
              'invalid',
              'indeterminate',
            ].contains(signer['timestampStatus']))
              _CheckRow(
                'Marca temporale',
                signer['timestampStatus'] == 'invalid'
                    ? 'Non valida'
                    : 'Verifica non conclusa',
                signer['timestampStatus'] == 'invalid'
                    ? CheckOutcome.negative
                    : CheckOutcome.indeterminate,
              ),
            if ('${signer['signingTime'] ?? ''}'.isNotEmpty)
              Text(
                tr(
                  context,
                  "Data dichiarata dal firmatario (non verificata): {p0}",
                  [tr(context, verificationDate(signer['signingTime']))],
                ),
              ),
            if (signer['historicalStatus'] == 'valid_at_timestamp')
              Text(tr(context, historicalLabel(signer))),
            ExpansionTile(
              title: Text(
                tr(context, "Dettagli del firmatario {p0}", [index + 1]),
              ),
              tilePadding: EdgeInsets.zero,
              children: [
                _CheckRow(
                  'Integrità crittografica',
                  signer['signatureValid'] == true
                      ? 'valido'
                      : signer['signatureValid'] == false
                      ? 'non valido'
                      : 'non determinato',
                  booleanOutcome(signer['signatureValid']),
                ),
                _CheckRow(
                  'Certificato nel periodo di validità',
                  signer['certificateWithinValidity'] == true
                      ? 'valido'
                      : signer['certificateWithinValidity'] == false
                      ? 'fuori dal periodo attuale'
                      : 'non determinato',
                  booleanOutcome(signer['certificateWithinValidity']),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr(context, trustChainLabel(signer))),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, "Revoca del firmatario: {p0}", [
                      tr(context, revocationLabel(signer['revocationStatus'])),
                    ]),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, "Revoca della catena: {p0}", [
                      tr(
                        context,
                        revocationLabel(signer['chainRevocationStatus']),
                      ),
                    ]),
                  ),
                ),
                if ('${signer['issuer'] ?? ''}'.isNotEmpty)
                  SelectableText(
                    tr(context, "Emittente: {p0}", [signer['issuer']]),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, "Marca della firma: {p0}", [
                      tr(context, timestampLabel(signer['timestampStatus'])),
                    ]),
                  ),
                ),
                if (timestampDetail(signer['timestampReason']).isNotEmpty)
                  Text(tr(context, timestampDetail(signer['timestampReason']))),
                if (signer['timestampStatus'] == 'verified')
                  Text(
                    tr(context, "Data della marca (UTC): {p0}", [
                      tr(context, verificationDate(signer['timestampTime'])),
                    ]),
                  ),
                if (signer['historicalStatus'] != 'valid_at_timestamp')
                  Text(tr(context, historicalLabel(signer))),
                if (historicalDetail(signer['historicalReason']).isNotEmpty)
                  Text(
                    tr(context, historicalDetail(signer['historicalReason'])),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.label, this.description, this.outcome);
  final String label, description;
  final CheckOutcome outcome;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          switch (outcome) {
            CheckOutcome.positive => Icons.check_circle_outline,
            CheckOutcome.negative => Icons.error_outline,
            CheckOutcome.indeterminate => Icons.help_outline,
          },
          color: switch (outcome) {
            CheckOutcome.positive =>
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.green.shade300
                  : Colors.green.shade700,
            CheckOutcome.negative => Theme.of(context).colorScheme.error,
            CheckOutcome.indeterminate =>
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.orange.shade300
                  : Colors.orange.shade800,
          },
          size: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label == 'Firma'
                ? tr(context, 'Firma: {p0}', [tr(context, description)])
                : tr(context, "{p0}: {p1}", [
                    tr(context, label),
                    tr(context, description),
                  ]),
            softWrap: true,
          ),
        ),
      ],
    ),
  );
}

String verificationProblemMessage(Map result, {bool extraction = false}) {
  final code = result['code'];
  final unreadable = const {
    'input_missing',
    'document_unreadable',
    'document_unreadable_or_too_large',
    'pdf_invalid',
    'invalid_format',
  }.contains(code);
  return code == 'document_changed'
      ? 'Il documento è cambiato. Ripeti la verifica sul file aggiornato.'
      : unreadable
      ? 'Seleziona un file PDF o P7M leggibile, non vuoto e di dimensioni non superiori a 256 MiB.'
      : code == 'network_configuration_required'
      ? 'Controlla o ripristina la configurazione della connessione in Impostazioni, poi ripeti la verifica.'
      : code == 'output_exists'
      ? 'Scegli un nuovo nome: i file esistenti non vengono sovrascritti.'
      : extraction
      ? 'Il contenuto non è stato salvato. Scegli una destinazione nuova e riprova.'
      : 'Il controllo non è stato completato. Puoi ripeterlo o scegliere un altro documento. Un problema di connessione non rende la firma non valida.';
}

class VerificationProblem extends StatelessWidget {
  const VerificationProblem({
    super.key,
    required this.result,
    this.extraction = false,
  });
  final Map result;
  final bool extraction;
  @override
  Widget build(BuildContext context) {
    final code = result['code'];
    final unreadable = const {
      'input_missing',
      'document_unreadable',
      'document_unreadable_or_too_large',
      'pdf_invalid',
      'invalid_format',
    }.contains(code);
    final title = extraction
        ? 'Estrazione non completata'
        : unreadable
        ? 'Documento non leggibile'
        : 'Verifica non completata';
    final message = verificationProblemMessage(result, extraction: extraction);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, title),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(tr(context, message), softWrap: true),
            ExpansionTile(
              title: Text(tr(context, "Dettagli tecnici")),
              tilePadding: EdgeInsets.zero,
              children: [
                if ('${result['message'] ?? ''}'.isNotEmpty)
                  SelectableText(tr(context, '${result['message']}')),
                SelectableText(
                  tr(context, "{p0}{p1}", [
                    result['code'] ?? 'verification_incomplete',
                    result['nativeCode'] == null
                        ? ''
                        : tr(context, ' · codice nativo {p0}', [
                            result['nativeCode'],
                          ]),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.result});
  final JsonResult result;
  @override
  Widget build(BuildContext context) => AppNotification(
    event: result,
    message: result['message'] as String? ?? 'Operazione non completata',
    title: 'Operazione non completata',
    error: true,
    details: [
      if (result['code'] != null) '${result['code']}',
      if (result['nativeCode'] != null)
        tr(context, 'Codice nativo: {p0}', [result['nativeCode']]),
    ].join('\n'),
  );
}
