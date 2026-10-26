// SPDX-License-Identifier: BSD-3-Clause
import 'dart:convert';

import 'app_localizations.dart';
import 'desktop_page_body.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

List<String> droppedDocumentPaths(Iterable<String> paths, {String? rawText}) {
  final unique = paths.where((path) => path.isNotEmpty).toSet();
  if (unique.isNotEmpty) return unique.toList();
  // Linux STRING/URI targets may include comments or line endings. A portal
  // transfer key is never a path; only explicit local paths can be recovered.
  for (final line in const LineSplitter().convert(rawText ?? '')) {
    if (line.isEmpty || line.startsWith('#')) continue;
    try {
      final uri = Uri.tryParse(line);
      if (uri?.scheme == 'file') {
        unique.add(uri!.toFilePath());
      } else if (line.startsWith('/')) {
        unique.add(line);
      }
    } on UnsupportedError {
      // Remote file authorities do not identify a local document.
    } on FormatException {
      // A malformed URI must not become a relative filesystem path.
    }
  }
  return unique.toList();
}

class DocumentDropZone extends StatefulWidget {
  const DocumentDropZone({
    super.key,
    required this.enabled,
    required this.onPaths,
    required this.child,
  });
  final bool enabled;
  final Future<void> Function(List<String>) onPaths;
  final Widget child;
  @override
  State<DocumentDropZone> createState() => _DocumentDropZoneState();
}

class _DocumentDropZoneState extends State<DocumentDropZone> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => DropTarget(
    enable: widget.enabled,
    onDragEntered: (_) {
      if (widget.enabled) setState(() => hover = true);
    },
    onDragExited: (_) => setState(() => hover = false),
    onDragDone: (details) async {
      setState(() => hover = false);
      if (widget.enabled) {
        await widget.onPaths(
          droppedDocumentPaths(
            details.files.map((f) => f.path),
            rawText: details.rawText,
          ),
        );
      }
    },
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: hover && widget.enabled
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            // Leave room for the heading, signing steps and drag hint. Natural
            // content height still wins on small windows or with large text.
            constraints: BoxConstraints(
              minHeight:
                  (DesktopPageViewport.maybeOf(context)?.height ?? 0) * .65,
            ),
            child: widget.child,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(tr(context, "Puoi anche trascinare qui un documento.")),
          ),
        ],
      ),
    ),
  );
}
