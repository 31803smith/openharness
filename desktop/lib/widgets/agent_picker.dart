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

  @override
  Widget build(BuildContext context) {
    final other = !quickAgents.contains(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final id in quickAgents) ...[
              Expanded(
                child: Semantics(
                  selected: value == id,
                  child: TextButton.icon(
                    key: ValueKey('new-agent-quick-$id'),
                    onPressed: () => onChanged(id),
                    icon: EngineMark(engine: id, size: 18),
                    label: Text(
                      id == 'claude' ? 'Claude Code' : engineIdentity(id).label,
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
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
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
              const SizedBox(width: 8),
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
