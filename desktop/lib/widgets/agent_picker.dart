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
  });
  final String value;
  final List<SelectOption<String>> options;
  final ValueChanged<String> onChanged;
  static const quickAgents = ['codex', 'claude', 'cursor'];

  @override
  Widget build(BuildContext context) => AppChoicePicker<String>(
    value: value,
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
    preferredValues: quickAgents,
    onChanged: onChanged,
    optionKey: (id) => ValueKey('new-agent-quick-$id'),
    moreKey: const Key('new-agent-engine-field'),
    moreLabel: 'More agents',
  );
}
