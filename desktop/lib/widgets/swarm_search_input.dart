import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/swarm_search.dart';
import '../state/swarm_navigation.dart';
import 'swarm_switcher.dart';

/// The same editable input in the centered picker and the New Agent page.
/// Flutter owns both the caret and result navigation; native chrome only opens it.
class SwarmSearchInput extends StatelessWidget {
  const SwarmSearchInput({
    super.key,
    required this.inputKey,
    required this.controller,
    required this.focusNode,
    required this.search,
    required this.onChoose,
    required this.onClose,
    required this.onChanged,
    this.onOpen,
    this.onNewAgent,
    this.groupId,
    this.onTapOutside,
    this.showClose = false,
    this.autofocus = true,
  });

  final Key inputKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final SwarmSearchController? search;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;
  final VoidCallback? onOpen;
  final VoidCallback? onNewAgent;
  final Object? groupId;
  final VoidCallback? onTapOutside;
  final bool showClose, autofocus;

  @override
  Widget build(BuildContext context) {
    final open = search != null;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(12),
        bottom: Radius.circular(open ? 0 : 12),
      ),
      borderSide: BorderSide(color: open ? Colors.transparent : Colors.white24),
    );
    final input = SwarmSearchKeys(
      search: search,
      editing: controller,
      onChoose: onChoose,
      onClose: onClose,
      onOpen: onOpen,
      onNewAgent: onNewAgent,
      child: TextField(
        key: inputKey,
        groupId: groupId ?? EditableText,
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: onOpen,
        onTapAlwaysCalled: true,
        onTapOutside: onTapOutside == null ? null : (_) => onTapOutside!(),
        onChanged: onChanged,
        style: const TextStyle(fontSize: 16, color: Colors.white),
        cursorColor: grid.AppPalette.swarmAccent,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: search?.hint ?? 'Find an existing agent…',
          hintStyle: const TextStyle(fontSize: 16, color: Colors.white60),
          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white60),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 52,
            minHeight: 56,
          ),
          suffixIcon: showClose
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton(
                    onPressed: onClose,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white60,
                      minimumSize: const Size(36, 28),
                    ),
                    child: const Text('esc', style: TextStyle(fontSize: 11)),
                  ),
                )
              : null,
          filled: true,
          fillColor: open
              ? grid.AppPalette.swarmSearchSurface
              : const Color(0xa6111521),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          isDense: true,
          border: border,
          enabledBorder: border,
          focusedBorder: border,
        ),
      ),
    );
    if (!showClose || search?.adding != true || onNewAgent == null) {
      return input;
    }
    return Row(
      children: [
        Expanded(child: input),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 14),
          child: FilledButton.icon(
            key: const ValueKey('swarm-search-new-agent'),
            onPressed: search!.canCreate ? onNewAgent : null,
            style: FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.swarmAccent,
              foregroundColor: grid.AppPalette.swarmField,
              minimumSize: const Size(148, 42),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add, size: 20),
            label: const Text(
              'Create Agent',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
