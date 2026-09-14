import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/pane_arrangement.dart';
import '../theme/app_theme.dart';

/// Reveals split controls inside the pane, leaving the resize gap untouched.
/// Hover state stays here so pointer movement never rebuilds the terminal.
class PaneSplitEdges extends StatefulWidget {
  const PaneSplitEdges({
    super.key,
    required this.child,
    required this.enabled,
    required this.canSplitRight,
    required this.canSplitDown,
    required this.onSplit,
  });

  final Widget child;
  final bool enabled, canSplitRight, canSplitDown;
  final ValueChanged<PaneResizeAxis>? onSplit;

  @override
  State<PaneSplitEdges> createState() => _PaneSplitEdgesState();
}

class _PaneSplitEdgesState extends State<PaneSplitEdges> {
  static const _buttonSize = 32.0;
  static const _inset = 8.0;
  static const _edgeWidth = 44.0;
  PaneResizeAxis? _edge;
  Size _size = Size.zero;

  @override
  void didUpdateWidget(PaneSplitEdges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _edge = null;
  }

  void _reveal(PaneResizeAxis? edge) {
    if (_edge == edge) return;
    setState(() => _edge = edge);
  }

  void _hover(PointerHoverEvent event) {
    if (!widget.enabled || event.buttons != 0) return;
    final point = event.localPosition;
    // Leave the header controls and both bottom corners alone. Once revealed,
    // the button itself stays inside the same hover band as the edge.
    final bottom =
        point.dy >= _size.height - _edgeWidth &&
        point.dx >= _edgeWidth &&
        point.dx <= _size.width - _edgeWidth;
    final right =
        point.dx >= _size.width - _edgeWidth &&
        point.dy >= 60 &&
        point.dy < _size.height - _edgeWidth;
    _reveal(
      bottom
          ? PaneResizeAxis.y
          : right
          ? PaneResizeAxis.x
          : null,
    );
  }

  Rect _buttonRect(PaneResizeAxis axis) => axis == PaneResizeAxis.x
      ? Rect.fromLTWH(
          _size.width - _inset - _buttonSize,
          (_size.height - _buttonSize) / 2,
          _buttonSize,
          _buttonSize,
        )
      : Rect.fromLTWH(
          (_size.width - _buttonSize) / 2,
          _size.height - _inset - _buttonSize,
          _buttonSize,
          _buttonSize,
        );

  void _pressed(PointerDownEvent event) {
    final edge = _edge;
    if (edge != null && !_buttonRect(edge).contains(event.localPosition)) {
      _reveal(null);
    }
  }

  Widget _button(PaneResizeAxis axis) {
    final visible = widget.enabled && _edge == axis;
    final right = axis == PaneResizeAxis.x;
    final available = right ? widget.canSplitRight : widget.canSplitDown;
    final label = right ? 'Split right' : 'Split down';
    return Positioned.fromRect(
      rect: _buttonRect(axis),
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeFocus(
          excluding: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              child: IconButton(
                key: ValueKey(right ? 'pane-split-right' : 'pane-split-down'),
                tooltip: available
                    ? label
                    : right
                    ? 'Make this pane wider to split right'
                    : 'Make this pane taller to split down',
                onPressed: available && widget.onSplit != null
                    ? () {
                        _reveal(null);
                        widget.onSplit!(axis);
                      }
                    : null,
                icon: const Icon(LucideIcons.plus, size: 18),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(_buttonSize),
                  minimumSize: const Size.square(_buttonSize),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  foregroundColor: grid.AppPalette.swarmAccent,
                  disabledForegroundColor: AppColors.mutedStrong,
                  backgroundColor: AppColors.surface,
                  disabledBackgroundColor: AppColors.surface,
                  hoverColor: grid.AppSurface.hoverFill,
                  shape: CircleBorder(
                    side: BorderSide(color: AppColors.borderStrong),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return MouseRegion(
          onHover: _hover,
          onExit: (_) => _reveal(null),
          child: Listener(
            onPointerDown: _pressed,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                _button(PaneResizeAxis.x),
                _button(PaneResizeAxis.y),
              ],
            ),
          ),
        );
      },
    );
  }
}
