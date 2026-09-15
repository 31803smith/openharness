import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_select_field.dart';
import 'engine_identity.dart';

class AgentPicker extends StatelessWidget {
  const AgentPicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String value;
  final List<SelectOption<String>> options;
  final ValueChanged<String> onChanged;
  static const quickAgents = ['codex', 'claude', 'cursor'];

  static String _label(String id) =>
      id == 'claude' ? 'Claude Code' : engineIdentity(id).label;

  @override
  Widget build(BuildContext context) {
    final other = !quickAgents.contains(value);
    final textStyle = TextStyle(
      fontFamily: grid.AppFont.sans,
      fontFamilyFallback: grid.AppFont.sansFallback,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            );
            var minimumWidth = 0.0;
            for (final id in quickAgents) {
              painter.text = TextSpan(text: _label(id), style: textStyle);
              painter.layout();
              // Icon, label gap and horizontal button padding.
              final width = painter.width + 18 + 8 + 16;
              if (width > minimumWidth) minimumWidth = width;
            }
            painter.dispose();
            final compactWidth = (constraints.maxWidth - 42 - 24) / 3;
            final pairWidth = (constraints.maxWidth - 8) / 2;
            final buttonWidth = compactWidth >= minimumWidth
                ? compactWidth
                : pairWidth >= minimumWidth
                ? pairWidth
                : constraints.maxWidth;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in quickAgents) ...[
                  SizedBox(
                    width: buttonWidth,
                    child: Semantics(
                      selected: value == id,
                      child: TextButton.icon(
                        key: ValueKey('new-agent-quick-$id'),
                        onPressed: () => onChanged(id),
                        icon: EngineMark(engine: id, size: 18),
                        label: Text(
                          _label(id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: grid.AppPalette.textPrimary,
                          backgroundColor: value == id
                              ? grid.AppSurface.recessHover
                              : grid.AppSurface.recess,
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: textStyle,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: value == id
                                  ? grid.AppPalette.accentOnSurface
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                Tooltip(
                  message: other
                      ? '${engineIdentity(value).label} selected · More agents'
                      : 'More agents',
                  child: AppSelectField<String>(
                    key: const Key('new-agent-engine-field'),
                    value: value,
                    options: options,
                    onChanged: onChanged,
                    width: 42,
                    height: 38,
                    trigger: Icon(
                      Icons.more_horiz,
                      size: 20,
                      color: other
                          ? grid.AppPalette.accentOnSurface
                          : grid.AppPalette.textSecondary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (other)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                EngineMark(engine: value, size: 18),
                const SizedBox(width: 8),
                Text(
                  engineIdentity(value).label,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.check,
                  size: 14,
                  color: grid.AppPalette.textSecondary,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
