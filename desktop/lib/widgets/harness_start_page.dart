import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import 'swarm_search_input.dart';
import 'swarm_switcher.dart';

/// The Open Harness input, results and navigation, revealed on the start page
/// only when the user chooses to search.
class HarnessStartPage extends StatefulWidget {
  const HarnessStartPage({
    super.key,
    required this.focusNode,
    required this.createSearch,
    required this.onNew,
    required this.onChoose,
  });
  final FocusNode focusNode;
  final SwarmSearchController Function() createSearch;
  final VoidCallback onNew;
  final ValueChanged<SwarmSearchSelection> onChoose;
  @override
  State<HarnessStartPage> createState() => _HarnessStartPageState();
}

class _HarnessStartPageState extends State<HarnessStartPage> {
  final _query = TextEditingController();
  FocusNode get _focus => widget.focusNode;
  final _pickerFocus = FocusNode(
    debugLabel: 'Start page picker',
    canRequestFocus: false,
  );
  final _searchGroup = Object();
  SwarmSearchController? _search;
  SwarmSearchDraft? _draft;
  bool get _showResults => _search != null;

  void _open() {
    // Commands can replace the editor value without a TextField onChanged.
    // Reveal results for the visible text, including on keyboard-only entry.
    if (_search == null) {
      final search = widget.createSearch();
      if (_draft case final draft?) search.restoreDraft(draft);
      search.setQuery(_query.text);
      setState(() => _search = search);
    } else {
      _search!.setQuery(_query.text);
    }
    _focus.requestFocus();
  }

  void _close() {
    final search = _search;
    if (search != null) {
      _draft = search.draft;
      setState(() => _search = null);
      search.dispose();
    }
    _pickerFocus.unfocus();
  }

  void _choose(SwarmSearchSelection selection) {
    _close();
    widget.onChoose(selection);
  }

  void _new() {
    _close();
    widget.onNew();
  }

  Widget _action({required bool create}) {
    final label = create ? 'New Harness' : 'Open Harness';
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (create) ...[
          const Icon(LucideIcons.plus300, size: 18),
          const SizedBox(width: 8),
        ],
        Text(label),
      ],
    );
    const size = Size(140, 48);
    const padding = EdgeInsets.symmetric(horizontal: 20);
    return create
        ? FilledButton(
            key: const ValueKey('harness-start-new'),
            onPressed: _new,
            style: FilledButton.styleFrom(
              enabledMouseCursor: SystemMouseCursors.click,
              minimumSize: size,
              padding: padding,
              backgroundColor: grid.AppPalette.swarmAccent,
              foregroundColor: grid.AppPalette.swarmTabBar,
              shape: const StadiumBorder(),
            ),
            child: content,
          )
        : OutlinedButton(
            key: const ValueKey('harness-start-open'),
            onPressed: _open,
            style: OutlinedButton.styleFrom(
              enabledMouseCursor: SystemMouseCursors.click,
              minimumSize: size,
              padding: padding,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              shape: const StadiumBorder(),
            ),
            child: content,
          );
  }

  Widget _searchPanel() => TextFieldTapRegion(
    groupId: _searchGroup,
    child: Focus(
      focusNode: _pickerFocus,
      child: Material(
        color: _showResults
            ? grid.AppPalette.swarmSearchSurface
            : Colors.transparent,
        elevation: _showResults ? 12 : 0,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_showResults ? 12 : 30),
          side: _showResults
              ? const BorderSide(color: Colors.white24)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: SwarmSearchKeys(
          search: _search,
          editing: _query,
          onChoose: _choose,
          onClose: _close,
          onOpen: _open,
          onNewAgent: _new,
          onRefocus: _focus.requestFocus,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'Find a harness',
                child: SwarmSearchInput(
                  inputKey: const ValueKey('harness-start-search'),
                  controller: _query,
                  focusNode: _focus,
                  search: _search,
                  onClose: _close,
                  onChanged: (_) => _open(),
                  onOpen: _open,
                  onTapOutside: _close,
                  groupId: _searchGroup,
                  autofocus: true,
                  showClose: _showResults,
                  hintText: 'Find a harness',
                  rounded: true,
                  compact: true,
                ),
              ),
              if (_showResults) ...[
                const Divider(height: 1, color: Colors.white12),
                Flexible(
                  child: SizedBox(
                    height: 480,
                    child: SwarmSearchResults(
                      key: const ValueKey('harness-start-results'),
                      search: _search!,
                      sideBySideMinWidth: 700,
                      onChoose: _choose,
                      onRefocus: _focus.requestFocus,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _device({required bool compact}) {
    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Transform.scale(
        // Frame the device, which sits left of center in the original photo.
        scale: 1.7,
        alignment: const Alignment(-0.5, 0.08),
        child: Image.asset(
          'assets/harness_device.webp',
          width: compact ? 96 : 256,
          height: compact ? 54 : 144,
          fit: BoxFit.cover,
          semanticLabel: 'Harness Device',
        ),
      ),
    );
    const caption = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'Meet the Harness device',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ),
        SizedBox(width: 4),
        Icon(Icons.arrow_outward, size: 12, color: Colors.white70),
      ],
    );
    return Semantics(
      link: true,
      child: InkWell(
        key: const ValueKey('harness-device-link'),
        mouseCursor: SystemMouseCursors.click,
        onTap: () => launchUrl(
          Uri.parse('https://www.autonomous.ai/harness-device'),
          mode: LaunchMode.externalApplication,
        ),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: compact ? 320 : 256,
          child: compact
              ? Row(
                  children: [
                    photo,
                    const SizedBox(width: 12),
                    const Expanded(child: caption),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [photo, const SizedBox(height: 12), caption],
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search?.dispose();
    _query.dispose();
    _pickerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, entryConstraints) {
                        // Reserve the footer before laying out search, keeping
                        // both its top edge and the device still as results open.
                        final top = (constraints.maxHeight * 0.21)
                            .clamp(72.0, 220.0)
                            .clamp(
                              0.0,
                              (entryConstraints.maxHeight - 320).clamp(
                                24.0,
                                220.0,
                              ),
                            );
                        return Padding(
                          padding: EdgeInsets.only(top: top),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(child: _searchPanel()),
                              if (!_showResults) ...[
                                const SizedBox(height: 20),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _action(create: false),
                                    _action(create: true),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  _device(compact: constraints.maxHeight < 600),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
