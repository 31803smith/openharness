import 'package:flutter/material.dart';
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
    required this.createSearch,
    required this.onNew,
    required this.onChoose,
  });
  final SwarmSearchController Function() createSearch;
  final VoidCallback onNew;
  final ValueChanged<SwarmSearchSelection> onChoose;
  @override
  State<HarnessStartPage> createState() => _HarnessStartPageState();
}

class _HarnessStartPageState extends State<HarnessStartPage> {
  final _query = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Start page search');
  final _searchGroup = Object();
  late final _search = widget.createSearch();
  bool _showResults = false;

  void _open() {
    if (!_showResults) setState(() => _showResults = true);
    _focus.requestFocus();
  }

  void _close() {
    if (_showResults) setState(() => _showResults = false);
    _focus.unfocus();
  }

  void _choose(SwarmSearchSelection selection) {
    _close();
    widget.onChoose(selection);
  }

  void _new() {
    _close();
    widget.onNew();
  }

  @override
  void dispose() {
    _search.dispose();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            (constraints.maxHeight * 0.21).clamp(72, 220),
            24,
            64,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  const Text(
                    'Harness',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFieldTapRegion(
                    groupId: _searchGroup,
                    child: Material(
                      color: _showResults
                          ? grid.AppPalette.swarmSearchSurface
                          : Colors.transparent,
                      elevation: _showResults ? 12 : 0,
                      shadowColor: Colors.black54,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          _showResults ? 12 : 30,
                        ),
                        side: _showResults
                            ? const BorderSide(color: Colors.white24)
                            : BorderSide.none,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Semantics(
                            label: 'Find a harness',
                            child: SwarmSearchInput(
                              inputKey: const ValueKey('harness-start-search'),
                              controller: _query,
                              focusNode: _focus,
                              search: _showResults ? _search : null,
                              onChoose: _choose,
                              onClose: _close,
                              onChanged: (value) {
                                _search.setQuery(value);
                                _open();
                              },
                              onOpen: _open,
                              onNewAgent: _new,
                              onTapOutside: _close,
                              groupId: _searchGroup,
                              autofocus: false,
                              showClose: _showResults,
                              hintText: '',
                              rounded: true,
                            ),
                          ),
                          if (_showResults) ...[
                            const Divider(height: 1, color: Colors.white12),
                            SizedBox(
                              height: (constraints.maxHeight * 0.4).clamp(
                                168,
                                336,
                              ),
                              child: SwarmSearchResults(
                                key: const ValueKey('harness-start-results'),
                                search: _search,
                                onChoose: _choose,
                                onRefocus: _focus.requestFocus,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        key: const ValueKey('harness-start-open'),
                        onPressed: _open,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(160, 44),
                          backgroundColor: grid.AppPalette.swarmSearchSurface,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Open Harness'),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('harness-start-new'),
                        onPressed: _new,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New Harness'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(160, 44),
                          backgroundColor: grid.AppPalette.swarmAccent,
                          foregroundColor: grid.AppPalette.swarmTabBar,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 160),
                  Semantics(
                    link: true,
                    child: InkWell(
                      key: const ValueKey('harness-device-link'),
                      onTap: () => launchUrl(
                        Uri.parse('https://www.autonomous.ai/harness-device'),
                        mode: LaunchMode.externalApplication,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                'assets/harness_device.webp',
                                width: 192,
                                height: 120,
                                fit: BoxFit.cover,
                                semanticLabel: 'Harness Device',
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Meet Harness Device ↗',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Voice control for your agents, right on your desk.',
                              textAlign: TextAlign.center,
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
      ),
    );
  }
}
