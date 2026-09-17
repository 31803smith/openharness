import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/empty_state.dart';
import 'package:harness_mobile/state/app_state.dart';

import 'phone_navigation.dart';
import 'phone_search_field.dart';
import 'phone_search_folder_header.dart';
import 'phone_search_groups.dart';
import 'phone_search_index.dart';
import 'phone_search_row.dart';

/// One query over every agent the account can reach. Machines are not searched
/// here — they are on the terminal's `⋯` sheet.
///
/// A screen of its own rather than a field above either list, and that is the
/// whole point: the two tabs each answer half the question, and somebody who
/// remembers "that review thing" does not know which half holds it. This is the
/// phone's version of the desktop's Open Agent picker, down to the ranking — the
/// two share [phoneFieldMatchScore] so a query that finds an agent on the laptop
/// finds the same agent here.
///
/// ⚠️ It never asks a machine anything. Keystrokes filter the cached index and
/// nothing else, so typing on a phone with two bars of signal stays instant and
/// costs no data.
///
/// Returns when the search closes, so a caller whose own chrome depends on
/// being the top route can rebuild — see `terminal_page.dart`, where the header
/// buttons hide behind a keyboard this page did not raise.
Future<void> openPhoneSearch(BuildContext context, AppNotifier notifier) =>
    Navigator.of(context)
        .push(phoneRoute((_) => PhoneSearchPage(notifier: notifier)));

class PhoneSearchPage extends StatefulWidget {
  const PhoneSearchPage({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<PhoneSearchPage> createState() => _PhoneSearchPageState();
}

class _PhoneSearchPageState extends State<PhoneSearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Phone search');
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final all = phoneSearchIndex(widget.notifier);
      final rows = rankPhoneSearch(all, _query);
      final terms = phoneSearchTerms(_query);
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        // The keyboard is up for this page's whole life, so the body must shrink
        // rather than let the list run underneath it.
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              PhoneSearchField(
                controller: _controller,
                focus: _focus,
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _controller.clear();
                  setState(() => _query = '');
                  // Clearing is a step back into browsing, not out of the
                  // screen — the caret stays where the next query will go.
                  _focus.requestFocus();
                },
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: PhoneSearchResults(
                  notifier: widget.notifier,
                  rows: rows,
                  terms: terms,
                  query: _query,
                  total: all.length,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The ranked results, drawn — agents under their folders, then machines.
///
/// ⚠️ Public because two screens draw it: this page, and the terminal's own
/// in-place search (see `terminal_search.dart`), which expands out of the header
/// bar rather than pushing a route. The two must return the same rows in the
/// same order from the same query, or opening a result would walk a different
/// pager depending on where the search was started.
class PhoneSearchResults extends StatelessWidget {
  const PhoneSearchResults({
    super.key,
    required this.notifier,
    required this.rows,
    required this.terms,
    required this.query,
    required this.total,
    this.onOpen,
  });

  final AppNotifier notifier;
  final List<PhoneSearchResult> rows;
  final List<String> terms;
  final String query;
  final int total;

  /// Called the moment a row is tapped, before anything opens.
  ///
  /// ⚠️ For the in-place search, which is not a route and so is not popped by
  /// opening something. Its field still holds the keyboard, and the terminal it
  /// is covering is about to be replaced underneath it — this is what puts the
  /// search away first. Null on [PhoneSearchPage], where the pop does it.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    if (total == 0) {
      return const EmptyState(
        icon: LucideIcons.laptopMinimal300,
        title: 'Nothing to search yet',
        message: 'Link a machine and its agents will be findable from here.',
      );
    }
    if (rows.isEmpty) {
      return EmptyState.noMatches(
        compact: false,
        message: 'Nothing matches “${query.trim()}”.',
      );
    }

    final groups = phoneSearchGroups(rows);
    final agents = phoneSearchGroupedRows(groups);
    final now = DateTime.now();
    return ListView(
      // The keyboard is up and the finger is already on the glass; dragging the
      // list is how somebody reaches a result without putting it away first.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        // Agents under their folders. Machines are not searched here any more:
        // they live in the terminal's `⋯` sheet — see `machine_actions.dart`.
        for (final group in groups) ...[
          PhoneSearchFolderHeader(group: group),
          for (final row in group.rows)
            PhoneSearchRow(
              row: row,
              terms: terms,
              now: now,
              onTap: () {
                onOpen?.call();
                _openAgent(context, agents, row);
              },
            ),
        ],
      ],
    );
  }

  /// Opens the agent as a pager over the OTHER matching agents.
  ///
  /// The neighbours are the search results, not the Agents tab's list: swiping
  /// walks exactly what the query returned, which is the list the person was
  /// looking at when they tapped. Handing it the unfiltered index instead would
  /// swipe into agents the query had just excluded.
  ///
  /// ⚠️ [agents] is the GROUPED order, the one drawn — not the ranked [rows].
  /// Grouping pulls a folder's rows together, so the ranked list can hold a
  /// different agent at any given index than the screen does.
  void _openAgent(
    BuildContext context,
    List<PhoneSearchResult> agents,
    PhoneSearchResult row,
  ) {
    final entry = row.entry;
    if (entry == null || !entry.agent.terminalAvailable) return;
    // ⚠️ Built from [phoneSearchAgentEntries] rather than by unwrapping each
    // row here. A `?result.entry` collapse would silently SHORTEN this list if
    // an agent row ever arrived without its entry, and the pager walks it by
    // index — a shorter list than the one on screen sends a swipe to the wrong
    // agent, with nothing on screen to explain why.
    openAgentPager(context, notifier, phoneSearchAgentEntries(agents), entry);
  }
}
