// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

class CieCardIllustration extends StatelessWidget {
  const CieCardIllustration({super.key, required this.width});
  final double width;
  static const artworkLeftFraction = 29 / 256;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/cie-card.png',
    width: width,
    height: width * 162 / 256,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

class PairedCardIdentity extends StatelessWidget {
  const PairedCardIdentity({
    super.key,
    required this.name,
    required this.number,
  });
  final String name, number;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const CieCardIllustration(width: 144),
      const SizedBox(width: 18),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? tr(context, "Carta abbinata") : name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              number.isEmpty
                  ? tr(context, "Numero carta non disponibile")
                  : tr(context, "Numero carta: {p0}", [number]),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    ],
  );
}
