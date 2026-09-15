import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import 'harness_entry_actions.dart';
import 'harness_customize_pane.dart';
import 'swarm_search_input.dart';
import 'swarm_switcher.dart';

/// The Open Agent input, results and navigation, revealed on the start page
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
  final _customizeButtonFocus = FocusNode(debugLabel: 'Customize Harness');
  bool _customizing = false;
  SwarmSearchController? _search;
  SwarmSearchDraft? _draft;
  bool get _showResults => _search != null;

  void _customize() {
    _close();
    setState(() => _customizing = true);
  }

  void _closeCustomization() {
    setState(() => _customizing = false);
    _customizeButtonFocus.requestFocus();
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
          borderRadius: BorderRadius.circular(32),
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
                label: 'Find an agent',
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
                  hintText: 'Find an agent',
                  rounded: true,
                  prominent: true,
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

  /// The product strip along the bottom of the page (mockup/device-strip-final.html).
  ///
  /// What stood here before was the studio photograph — a light-grey box with
  /// the dial in it — cropped into a rounded rectangle and set in the darkest
  /// corner of a dark page, where a pale rectangle reads as a broken image
  /// rather than a product. The asset is a cutout now: the render with its
  /// ground keyed out, so the device — face, bezel, body, stand — floats on
  /// whatever the page is painted, inside a glass strip the width of the
  /// search field, with a name, one line on what it does, and a Learn more.
  Widget _device({required bool compact}) {
    final height = compact ? 84.0 : 120.0;
    return Semantics(
      link: true,
      child: InkWell(
        key: const ValueKey('harness-device-link'),
        mouseCursor: SystemMouseCursors.click,
        onTap: _openDevicePage,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: grid.AppTheme.pick(
              const Color(0x0A000000),
              const Color(0x0EFFFFFF),
            ),
            border: Border.all(color: grid.AppGlass.hair),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Image.asset(
                  'assets/harness_device.png',
                  height: height - 12,
                  fit: BoxFit.contain,
                  semanticLabel: 'Harness Device',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meet the Harness device',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: grid.AppFont.semibold,
                        color: grid.AppPalette.textPrimary,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        'A device for your agents — scroll, switch panes, '
                        'give voice commands.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: grid.AppPalette.textFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: grid.AppGlass.hair),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Learn more',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: grid.AppFont.semibold,
                        color: grid.AppPalette.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_outward,
                      size: 12,
                      color: grid.AppPalette.textPrimary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _openDevicePage() => launchUrl(
    Uri.parse('https://www.autonomous.ai/harness-device'),
    mode: LaunchMode.externalApplication,
  );

  @override
  void dispose() {
    _search?.dispose();
    _query.dispose();
    _pickerFocus.dispose();
    _customizeButtonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidth = constraints.maxWidth.clamp(0.0, 420.0);
        final sideBySide = constraints.maxWidth >= 1000;
        return Row(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _page(),
                  Positioned(
                    right: 20,
                    bottom: 16,
                    child: FilledButton.icon(
                      key: const ValueKey('harness-customize-button'),
                      focusNode: _customizeButtonFocus,
                      onPressed: _customizing
                          ? _closeCustomization
                          : _customize,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Customize Harness'),
                      style: FilledButton.styleFrom(
                        backgroundColor: grid.AppPalette.swarmAccent,
                        foregroundColor: grid.AppPalette.swarmTabBar,
                        minimumSize: const Size(0, 36),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  if (_customizing && !sideBySide)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: paneWidth,
                      child: HarnessCustomizePane(onClose: _closeCustomization),
                    ),
                ],
              ),
            ),
            if (_customizing && sideBySide)
              SizedBox(
                width: paneWidth,
                child: HarnessCustomizePane(onClose: _closeCustomization),
              ),
          ],
        );
      },
    );
  }

  Widget _page() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
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
                                HarnessEntryActions(
                                  onOpen: _open,
                                  onNew: _new,
                                  openKey: const ValueKey('harness-start-open'),
                                  newKey: const ValueKey('harness-start-new'),
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
