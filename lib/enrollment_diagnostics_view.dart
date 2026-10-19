// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

import 'enrollment.dart';

class EnrollmentDiagnosticsView extends StatelessWidget {
  const EnrollmentDiagnosticsView({
    super.key,
    required this.records,
    required this.readable,
    this.onRefresh,
    this.busy = false,
  });
  final List<EnrollmentRecord> records;
  final bool readable, busy;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(tr(context, "Diagnostica accesso ai siti")),
    childrenPadding: const EdgeInsets.all(16),
    children: [
      Text(
        tr(
          context,
          "Il rilevamento nel lettore e la disponibilità dell’identità per il browser sono controlli distinti. Un’identità non osservata non dimostra un errore di accesso. Questi controlli non richiedono il PIN e non provano il login a un sito.",
        ),
      ),
      const SizedBox(height: 12),
      if (onRefresh != null)
        TextButton(
          onPressed: busy ? null : onRefresh,
          child: Text(tr(context, "Aggiorna stato configurazione")),
        ),
      if (!readable)
        Text(tr(context, "Archivio degli abbinamenti non leggibile.")),
      if (records.isEmpty)
        Text(tr(context, "Nessuna CIE memorizzata da analizzare.")),
      for (var i = 0; i < records.length; i++) ...[
        const Divider(),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            tr(context, "Carta memorizzata {p0}", [i + 1]),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final entry in <String, String>{
          'Abbinamento per la firma': records[i].readyForSigning
              ? 'presente'
              : 'da completare',
          'Dati pubblici verificati': records[i].hasPublicData
              ? 'presenti'
              : 'assenti',
          'Certificato pubblicato per il browser': records[i].webProvisioned
              ? 'sì'
              : 'no',
          'Componente di sistema': records[i].componentAvailable
              ? 'disponibile'
              : 'non disponibile',
          'Identità esposta al sistema': !records[i].componentAvailable
              ? 'osservazione non disponibile'
              : records[i].identityObserved
              ? 'osservata'
              : 'non osservata al momento',
        }.entries)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              tr(context, "{p0}: {p1}", [
                tr(context, entry.key),
                tr(context, entry.value),
              ]),
            ),
          ),
      ],
    ],
  );
}
