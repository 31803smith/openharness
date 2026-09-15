import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_select_field.dart';

/// Three direct choices, with the complete list behind More. A selection from
/// that list takes the third slot, so the current value always stays visible.
class AppChoicePicker<T> extends StatefulWidget {
  const AppChoicePicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.optionKey,
    required this.moreLabel,
    this.moreKey,
    this.preferredValues = const [],
    this.showDetails = false,
  });

  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final Key Function(T) optionKey;
  final String moreLabel;
  final Key? moreKey;
  final List<T> preferredValues;
  final bool showDetails;

  @override
  State<AppChoicePicker<T>> createState() => _AppChoicePickerState<T>();
}

class _AppChoicePickerState<T> extends State<AppChoicePicker<T>> {
  ({T value})? _thirdChoice;

  List<SelectOption<T>> get _orderedOptions => [
    for (final preferred in widget.preferredValues)
      ...widget.options.where((option) => option.value == preferred),
    ...widget.options.where(
      (option) => !widget.preferredValues.contains(option.value),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _rememberThirdChoice();
  }

  @override
  void didUpdateWidget(covariant AppChoicePicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberThirdChoice();
  }

  void _rememberThirdChoice() {
    final remaining = _orderedOptions.skip(2);
    final selected = remaining
        .where((option) => option.value == widget.value)
        .firstOrNull;
    final previous = remaining
        .where((option) => option.value == _thirdChoice?.value)
        .firstOrNull;
    // Keep the extra choice available while switching between the first two.
    // If it disappears from the list, fall back to the ordinary third choice.
    final third = selected ?? previous ?? remaining.firstOrNull;
    _thirdChoice = third == null ? null : (value: third.value);
  }

  List<SelectOption<T>> get _visibleOptions => [
    ..._orderedOptions.take(2),
    if (_thirdChoice != null)
      ...widget.options.where((option) => option.value == _thirdChoice!.value),
  ];

  void _choose(T next) {
    if (next != widget.value) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final visible = _visibleOptions;
    if (visible.isEmpty) return const SizedBox.shrink();
    final hasMore = widget.options.length > visible.length;
    final textStyle = TextStyle(
      fontFamily: AppFont.sans,
      fontFamilyFallback: AppFont.sansFallback,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    final detailStyle = textStyle.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
    );
    final height = widget.showDetails ? 58.0 : 44.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: scaler,
        );
        var minimumWidth = 0.0;
        for (final option in visible) {
          painter.text = TextSpan(text: option.label, style: textStyle);
          painter.layout();
          var labelWidth = painter.width;
          if (widget.showDetails && option.detail != null) {
            painter.text = TextSpan(text: option.detail, style: detailStyle);
            painter.layout();
            labelWidth = math.max(labelWidth, painter.width);
          }
          // Long custom names truncate with their full text in the tooltip.
          // Larger system text gets wider choices and additional rows.
          final width =
              math.min(labelWidth, scaler.scale(13) * 9) +
              (option.leading == null ? 0 : 26) +
              42;
          minimumWidth = math.max(minimumWidth, width);
        }
        painter.dispose();
        const gap = 8.0;
        const moreWidth = 44.0;
        final rowWidth =
            (constraints.maxWidth -
                (hasMore ? moreWidth + gap : 0) -
                gap * (visible.length - 1)) /
            visible.length;
        final pairWidth = (constraints.maxWidth - gap) / 2;
        final buttonWidth = rowWidth >= minimumWidth
            ? rowWidth
            : pairWidth >= minimumWidth
            ? pairWidth
            : constraints.maxWidth;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final option in visible)
              SizedBox(
                width: buttonWidth,
                child: _choice(option, textStyle, detailStyle, height),
              ),
            if (hasMore)
              Semantics(
                label: widget.moreLabel,
                button: true,
                child: Tooltip(
                  message: widget.moreLabel,
                  child: AppSelectField<T>(
                    key: widget.moreKey,
                    value: widget.value,
                    options: widget.options,
                    onChanged: _choose,
                    width: moreWidth,
                    height: height,
                    trigger: Icon(
                      Icons.more_horiz,
                      size: 20,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _choice(
    SelectOption<T> option,
    TextStyle textStyle,
    TextStyle detailStyle,
    double height,
  ) {
    final selected = widget.value == option.value;
    final foreground = selected
        ? AppPalette.accentOnSurface
        : AppPalette.textPrimary;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Tooltip(
        message: [option.label, option.detail, option.note].nonNulls.join('\n'),
        child: TextButton(
          key: widget.optionKey(option.value),
          onPressed: () => _choose(option.value),
          style:
              TextButton.styleFrom(
                foregroundColor: foreground,
                backgroundColor: selected
                    ? AppPalette.accentOnSurface.withValues(alpha: .16)
                    : AppSurface.recess,
                minimumSize: Size(0, height),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                textStyle: textStyle,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.focused)
                        ? AppPalette.accentOnSurface
                        : Colors.transparent,
                  ),
                ),
              ),
          child: Row(
            children: [
              if (option.leading != null) ...[
                IconTheme(
                  data: IconThemeData(size: 18, color: foreground),
                  child: option.leading!(),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.showDetails && option.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        option.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: detailStyle.copyWith(
                          color: selected
                              ? foreground
                              : AppPalette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 16,
                child: selected
                    ? const ExcludeSemantics(child: Icon(Icons.check, size: 16))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
