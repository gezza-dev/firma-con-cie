// SPDX-License-Identifier: BSD-3-Clause
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The usable page area, excluding navigation, header and scrolling padding.
class DesktopPageViewport extends InheritedWidget {
  const DesktopPageViewport({
    super.key,
    required this.size,
    required super.child,
  });

  final Size size;

  static Size? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopPageViewport>()?.size;

  @override
  bool updateShouldNotify(DesktopPageViewport oldWidget) =>
      size != oldWidget.size;
}

/// Fills the current viewport while allowing long pages to scroll vertically.
class DesktopPageBody extends StatelessWidget {
  const DesktopPageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const padding = EdgeInsets.fromLTRB(28, 8, 28, 28);
      final size = Size(
        math.max(0, constraints.maxWidth - padding.horizontal),
        math.max(0, constraints.maxHeight - padding.vertical),
      );
      return DesktopPageViewport(
        size: size,
        child: SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: size.width,
              maxWidth: size.width,
              minHeight: size.height,
            ),
            child: child,
          ),
        ),
      );
    },
  );
}
