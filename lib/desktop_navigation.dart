// SPDX-License-Identifier: BSD-3-Clause
import 'package:flutter/material.dart';

class DesktopNavigationDestination {
  const DesktopNavigationDestination({
    required this.icon,
    required this.label,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final bool disabled;
}

/// Shared desktop menu. Each complete row is an interactive Material surface,
/// so hovering the label or its surrounding space gives the same feedback.
class DesktopNavigation extends StatelessWidget {
  const DesktopNavigation({
    super.key,
    required this.extended,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.leading,
    required this.destinations,
  });

  final bool extended;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final Widget leading;
  final List<DesktopNavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rail = theme.navigationRailTheme;
    return SizedBox(
      width: extended ? 256 : 72,
      height: double.infinity,
      child: Material(
        color: rail.backgroundColor ?? colors.surface,
        child: SingleChildScrollView(
          child: Column(
            children: [
              leading,
              for (var index = 0; index < destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: _destination(context, index),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destination(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rail = theme.navigationRailTheme;
    final destination = destinations[index];
    final selected = index == selectedIndex;
    final enabled = onDestinationSelected != null && !destination.disabled;
    final labelStyle = selected
        ? rail.selectedLabelTextStyle
        : rail.unselectedLabelTextStyle;
    final icon = Icon(destination.icon);
    final tile = ListTile(
      enabled: enabled,
      selected: selected,
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      selectedColor: colors.onSecondaryContainer,
      textColor: colors.onSurfaceVariant,
      iconColor: colors.onSurfaceVariant,
      selectedTileColor: colors.secondaryContainer,
      hoverColor: colors.primary.withValues(alpha: .10),
      mouseCursor: WidgetStateMouseCursor.clickable,
      titleTextStyle: labelStyle,
      leading: extended ? icon : null,
      title: extended ? Text(destination.label) : Center(child: icon),
      onTap: enabled ? () => onDestinationSelected!(index) : null,
    );
    final item = Semantics(selected: selected, child: tile);
    if (extended) return item;
    return Tooltip(message: destination.label, child: item);
  }
}
