import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../theme/app_theme.dart';

/// Direct pane controls, in a stable order even when an action is unavailable.
class PaneHeaderActions extends StatelessWidget {
  const PaneHeaderActions({
    super.key,
    required this.name,
    required this.zoomed,
    this.onZoom,
    this.onDelete,
    this.onClose,
  });

  final String name;
  final bool zoomed;
  final VoidCallback? onZoom, onDelete, onClose;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);

    Widget action(
      String tooltip,
      IconData icon,
      VoidCallback? callback, {
      bool destructive = false,
    }) => IconButton(
      tooltip: tooltip,
      onPressed: callback,
      icon: Icon(icon, size: 18),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size(28, 28)),
        minimumSize: const WidgetStatePropertyAll(Size(28, 28)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return grid.AppPalette.textFaint;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return destructive ? AppColors.danger : AppColors.text;
          }
          return AppColors.mutedStrong;
        }),
        overlayColor: WidgetStatePropertyAll(grid.AppSurface.hoverFill),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          zoomed ? 'Restore agents' : 'Zoom $name',
          zoomed ? LucideIcons.minimize : LucideIcons.maximize,
          onZoom,
        ),
        const SizedBox(width: 2),
        action('Delete agent', LucideIcons.trash2, onDelete, destructive: true),
        const SizedBox(width: 2),
        action('Close pane', LucideIcons.x, onClose),
      ],
    );
  }
}
