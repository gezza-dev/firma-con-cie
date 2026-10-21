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
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
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
        );
        if (!showBack && onBack == null) return title;
        final back = Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: Text(tr(context, "Indietro")),
          ),
        );
        // A narrow or transitioning navigation rail must not squeeze the title
        // between two fixed spacers until it overflows the window vertically.
        if (constraints.maxWidth < 600) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [back, const SizedBox(height: 8), title],
          );
        }
        return Row(
          children: [
            SizedBox(width: 126, child: back),
            Expanded(child: title),
            const SizedBox(width: 126),
          ],
        );
      },
    ),
  );
}
