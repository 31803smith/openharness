import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/empty_state.dart';
import 'package:harness_mobile/state/app_state.dart';

import 'link_page.dart';
import 'phone_navigation.dart';
import 'phone_search_field.dart';
import 'phone_search_folder_header.dart';
import 'phone_search_groups.dart';
import 'phone_search_index.dart';
import 'phone_search_row.dart';
import 'phone_sheet.dart';
import 'phone_status.dart';
import 'unlink_machine.dart';

/// One query over everything the account can reach — agents and machines
/// together.
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
                child: _Results(
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

class _Results extends StatelessWidget {
  const _Results({
    required this.notifier,
    required this.rows,
    required this.terms,
    required this.query,
    required this.total,
  });

  final AppNotifier notifier;
  final List<PhoneSearchResult> rows;
  final List<String> terms;
  final String query;
  final int total;

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
    final machines = phoneSearchOfKind(rows, PhoneSearchKind.machine);
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
        // Agents under their folders, machines in a section of their own. The
        // two kinds open different things, and a machine row appearing between
        // two agents is read as another agent until the icon is noticed.
        for (final group in groups) ...[
          PhoneSearchFolderHeader(group: group),
          for (final row in group.rows)
            PhoneSearchRow(
              row: row,
              terms: terms,
              now: now,
              onTap: () => _openAgent(context, agents, row),
            ),
        ],
        if (machines.isNotEmpty) ...[
          _GroupLabel('Machines', count: machines.length),
          for (final row in machines)
            PhoneSearchRow(
              row: row,
              terms: terms,
              now: now,
              onTap: () => _openMachine(context, row),
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

  /// A machine that wants its password opens the form for it. One that is
  /// linked opens a sheet of what can be done TO it — reload its agents,
  /// re-enter its password, unlink this phone — and no longer a list of its
  /// agents: those are a swipe away in the terminal, and search already lists
  /// them above.
  ///
  /// Read at the tap, not when the row was drawn, so a machine that got linked
  /// while this page was open gets the sheet rather than a form it no longer
  /// needs.
  void _openMachine(BuildContext context, PhoneSearchResult row) {
    final machine = notifier.stateOf(row.machineId);
    if (machine == null) return;
    switch (phoneMachineStatusOf(machine)) {
      case PhoneMachineStatus.offline:
        return;
      case PhoneMachineStatus.needsPassword:
        openMachine(context, notifier, row.machineId);
        return;
      case PhoneMachineStatus.connecting || PhoneMachineStatus.ready:
        break;
    }
    final machineId = row.machineId;
    showPhoneSheet(
      context,
      title: machine.machine.displayName,
      actions: [
        PhoneSheetAction(
          icon: LucideIcons.refreshCw300,
          label: 'Reload agents',
          onTap: () => unawaited(notifier.reloadMachineData(machineId)),
        ),
        PhoneSheetAction(
          icon: LucideIcons.keyRound300,
          label: 'Re-enter password…',
          onTap: () => Navigator.of(context).push(
            phoneRoute(
              (_) => LinkPage(notifier: notifier, machineId: machineId),
            ),
          ),
        ),
        // No confirmation, the same as the Machines tab: this sheet is the step
        // between the tap and the unlink.
        PhoneSheetAction(
          icon: LucideIcons.unlink300,
          label: 'Unlink this phone',
          destructive: true,
          onTap: () => unawaited(unlinkThisPhone(context, notifier, machine)),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: AppPalette.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: TextStyle(
              color: AppPalette.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFeatures: AppFont.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
