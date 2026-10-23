// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';

import 'app_localizations.dart';

class AppNotificationScope extends InheritedWidget {
  const AppNotificationScope({
    super.key,
    required this.onVisibilityChanged,
    required super.child,
  });
  final ValueChanged<bool> onVisibilityChanged;
  @override
  bool updateShouldNotify(AppNotificationScope oldWidget) => false;
}

final _queues = Expando<_NotificationQueue>();

class _NotificationQueue {
  Future<void> tail = Future<void>.value();
}

// One notification at a time per window; rebuilding, changing theme or
// returning from a dialog must not replay an already presented event.
Future<void> showAppNotification(
  BuildContext context, {
  required String message,
  String title = 'Firma con CIE',
  String? details,
  bool error = false,
  String buttonLabel = 'Chiudi',
  bool Function()? isCurrent,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final queue = _queues[navigator] ??= _NotificationQueue();
  final visibility = context
      .getInheritedWidgetOfExactType<AppNotificationScope>()
      ?.onVisibilityChanged;
  final task = queue.tail.then((_) async {
    if (!context.mounted || isCurrent?.call() == false) return;
    visibility?.call(true);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(
                error ? Icons.cancel_outlined : Icons.info_outline,
                color: error
                    ? Theme.of(dialogContext).colorScheme.error
                    : Theme.of(dialogContext).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(tr(dialogContext, title))),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(dialogContext, message), softWrap: true),
                  if (details != null && details.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      tr(dialogContext, details),
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr(dialogContext, buttonLabel)),
            ),
          ],
        ),
      );
    } finally {
      visibility?.call(false);
    }
  });
  queue.tail = task.catchError((Object _) {});
  return task;
}

class AppNotification extends StatefulWidget {
  const AppNotification({
    super.key,
    this.message,
    this.event,
    this.details,
    this.title = 'Firma con CIE',
    this.error = false,
    this.enabled = true,
    this.onDismissed,
  });
  final String? message, details;
  final String title;
  final Object? event;
  final bool error, enabled;
  final VoidCallback? onDismissed;
  @override
  State<AppNotification> createState() => _AppNotificationState();
}

class _AppNotificationState extends State<AppNotification> {
  Object? _lastEvent;
  bool _scheduled = false;
  Object? get _event => widget.event ?? widget.message;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(AppNotification oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (widget.message == null) {
      _lastEvent = null;
      return;
    }
    if (_scheduled || !widget.enabled || _lastEvent == _event) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled = false;
      if (!mounted ||
          !widget.enabled ||
          widget.message == null ||
          _lastEvent == _event) {
        return;
      }
      final event = _event;
      final dismissed = widget.onDismissed;
      _lastEvent = event;
      await showAppNotification(
        context,
        message: widget.message!,
        title: widget.title,
        error: widget.error,
        details: widget.details,
        isCurrent: () => mounted && _event == event && widget.message != null,
      );
      if (mounted && _event == event) dismissed?.call();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
