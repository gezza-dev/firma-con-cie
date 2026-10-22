// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

class CieCardIllustration extends StatelessWidget {
  const CieCardIllustration({
    super.key,
    required this.width,
    this.inColor = true,
  });
  final double width;
  final bool inColor;
  static const artworkLeftFraction = 29 / 256;
  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/cie-card.png',
      width: width,
      height: width * 162 / 256,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    return inColor
        ? image
        : ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: image,
          );
  }
}

class PairedCardIdentity extends StatelessWidget {
  const PairedCardIdentity({
    super.key,
    required this.name,
    required this.number,
    this.present = true,
  });
  final String name, number;
  final bool present;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      CieCardIllustration(width: 144, inColor: present),
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
