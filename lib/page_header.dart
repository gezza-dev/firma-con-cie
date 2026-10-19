// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

import 'package:flutter/material.dart';

import 'app_flow.dart';

class ApplicationPageHeader extends StatelessWidget {
  const ApplicationPageHeader({
    super.key,
    required this.destination,
    this.onBack,
    this.showBack = false,
  });
  final AppDestination destination;
  final VoidCallback? onBack;
  final bool showBack;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
    child: Row(
      children: [
        SizedBox(
          width: 126,
          child: !showBack && onBack == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(tr(context, "Indietro")),
                  ),
                ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(
                  context,
                  destination == AppDestination.home
                      ? 'CIE ID'
                      : destination.label,
                ),
                key: const ValueKey('page-title'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (destination == AppDestination.home) ...[
                const SizedBox(height: 5),
                Text(
                  tr(context, "La tua Carta di Identità Elettronica"),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 126),
      ],
    ),
  );
}
