// SPDX-License-Identifier: BSD-3-Clause
import 'app_localizations.dart';

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
          color: hover && widget.enabled ? Colors.blue : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.child,
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(tr(context, "Puoi anche trascinare qui un documento.")),
          ),
        ],
      ),
    ),
  );
}
