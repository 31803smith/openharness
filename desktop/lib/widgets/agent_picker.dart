import 'package:flutter/material.dart';

import '../shared/widgets/app_choice_picker.dart';
import '../shared/widgets/app_select_field.dart';
import 'engine_identity.dart';

class AgentPicker extends StatelessWidget {
  const AgentPicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.compact = false,
    this.quiet = false,
  });
  final String value;
  final List<SelectOption<String>> options;
  final ValueChanged<String> onChanged;
  final bool compact;
  final bool quiet;
  static const quickAgents = ['codex', 'claude', 'cursor'];

  @override
  Widget build(BuildContext context) => AppChoicePicker<String>(
    value: value,
    compact: compact,
    quiet: quiet,
    options: [
      for (final option in options)
        SelectOption(
          value: option.value,
          label: option.value == 'claude' ? 'Claude Code' : option.label,
          note: option.note,
          detail: option.detail,
          leading: () => EngineMark(engine: option.value, size: 18),
          trailing: option.trailing,
        ),
    ],
    preferredValues: quiet
        ? const ['codex', 'claude', 'opencode']
        : quickAgents,
    onChanged: onChanged,
    optionKey: (id) => ValueKey('new-agent-quick-$id'),
    moreKey: const Key('new-agent-engine-field'),
    moreLabel: 'More agents',
  );
}
