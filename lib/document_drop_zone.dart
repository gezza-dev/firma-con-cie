// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';
import 'desktop_page_body.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

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
        await widget.onPaths(details.files.map((f) => f.path).toList());
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
