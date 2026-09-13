import 'package:flutter/material.dart';

import '../../shared/widgets/section_scaffold.dart';
import '../../shortcuts/shortcuts_list.dart';
import '../../shortcuts/app_keymap.dart';
import '../../shortcuts/keymap.dart';
import '../../shortcuts/keymap_settings.dart';

/// Settings ▸ Keyboard shortcuts — the same rows the ⌘/ sheet shows, in the
/// place someone looks when they don't yet know the sheet exists.
///
/// The sheet's own column used to be dropped in here whole, clamped to the
/// 460px it was drawn for; in a settings window that is a third of the width,
/// and the pane read as a dialog someone had pasted into a screen. It gets
/// [ShortcutsDeck] instead — the same rows, laid out across the room this
/// screen has.
class ShortcutsSection extends StatefulWidget {
  const ShortcutsSection({super.key});

  @override
  State<ShortcutsSection> createState() => _ShortcutsSectionState();
}

class _ShortcutsSectionState extends State<ShortcutsSection> {
  KeymapContext _contextKind = KeymapContext.workspace;

  @override
  Widget build(BuildContext context) {
    final hint = effectiveCommandHint(context, 'keyboard.help');
    return SectionScaffold(
      title: 'Keyboard shortcuts',
      subtitle: hint == null
          ? 'Your current shortcuts.'
          : 'Your current shortcuts. Press $hint to see them in your workspace.',
      // A SingleChildScrollView, never a ListView — same reason as Appearance
      // and Terminal: a lazy list keeps children across a rebuild and strands
      // them on the palette they first mounted with.
      child: SingleChildScrollView(
        child: Padding(
          // Room under the last card so a scrolled-to-bottom pane does not end
          // flush against the window edge.
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeymapSettings(
                contextKind: _contextKind,
                onContextChanged: (value) =>
                    setState(() => _contextKind = value),
              ),
              ShortcutsDeck(contextKind: _contextKind),
            ],
          ),
        ),
      ),
    );
  }
}
