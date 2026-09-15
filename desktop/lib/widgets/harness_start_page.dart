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
  final _searchSurface = GlobalKey();
  bool _revealScheduled = false;
  SwarmSearchController? _search;
  SwarmSearchDraft? _draft;
  bool get _showResults => _search != null;

  void _revealResults() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted || !_showResults || !_pickerFocus.hasFocus) return;
      // Keep the full search panel visible without changing its width.
      Scrollable.ensureVisible(
        _searchSurface.currentContext!,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

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

  Widget _searchPanel(BoxConstraints constraints) => TextFieldTapRegion(
    groupId: _searchGroup,
    child: Focus(
      focusNode: _pickerFocus,
      child: Material(
        key: _searchSurface,
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
                SizedBox(
                  height: (constraints.maxHeight * 0.54).clamp(260, 480),
                  child: SwarmSearchResults(
                    key: const ValueKey('harness-start-results'),
                    search: _search!,
                    sideBySideMinWidth: 700,
                    onChoose: _choose,
                    onRefocus: _focus.requestFocus,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

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
        if (_showResults) _revealResults();
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              (constraints.maxHeight * 0.21).clamp(72, 220),
              24,
              64,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _searchPanel(constraints),
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
                    const SizedBox(height: 160),
                    Semantics(
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
                          width: 256,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Transform.scale(
                                  // Frame the device, which sits left of center
                                  // in the original photo, without altering it.
                                  scale: 1.7,
                                  alignment: const Alignment(-0.5, 0.08),
                                  child: Image.asset(
                                    'assets/harness_device.webp',
                                    width: 256,
                                    height: 144,
                                    fit: BoxFit.cover,
                                    semanticLabel: 'Harness Device',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'The ultimate Harness setup',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_outward,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Scroll, switch panes, and give voice commands.',
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
