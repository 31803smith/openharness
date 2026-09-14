import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/swarm_search.dart';
import '../state/swarm_navigation.dart';
import 'swarm_switcher.dart';

/// The shared input for New Harness, Add and split searches.
/// Flutter owns the caret and result navigation; native chrome only opens it.
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
    this.hintText,
    this.rounded = false,
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
  final String? hintText;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final open = search != null;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(rounded && !open ? 30 : 12),
        bottom: Radius.circular(
          open
              ? 0
              : rounded
              ? 30
              : 12,
        ),
      ),
      borderSide: BorderSide(color: open ? Colors.transparent : Colors.white24),
    );
    return SwarmSearchKeys(
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
          hintText: search?.isCommandMode == true
              ? search!.hint
              : hintText ?? search?.hint ?? 'Find a harness',
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
  }
}
