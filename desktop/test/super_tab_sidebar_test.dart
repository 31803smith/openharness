import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/machine_resources.dart';
import 'package:harness/shared/theme/app_icons.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/super_tabs/controller.dart';
import 'package:harness/super_tabs/machine_status.dart';
import 'package:harness/super_tabs/machines.dart';
import 'package:harness/super_tabs/project_sidebar.dart';
import 'package:harness/super_tabs/section_heading.dart';
import 'package:harness/super_tabs/view.dart';

import 'support/super_tab_fixture.dart';
import 'swarm_state_test.dart' show createApp;

/// The Machines group's heading, wherever the sidebar is mounted.
Finder machinesHeading() => find.ancestor(
  of: find.text('Machines'),
  matching: find.byType(SuperTabSectionHeading),
);

/// The unread mark at the right end of a project or workgroup row.
Finder unreadDot(String groupId) => find.descendant(
  of: find.byKey(ValueKey('super-group-$groupId')),
  matching: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Unread messages',
  ),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'sidebar shares text alignment and preserves lead navigation at ${scale}x',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final app = createApp(connected: true);
        addTearDown(app.dispose);
        final server = ConversationServer();
        server.state['projects'] = [
          projectFixture('lead', 'web-project', 'lead'),
          projectFixture(
            'empty',
            'sample-project',
            'empty-lead',
            visibility: 'private',
          ),
        ];
        (server.state['conversations'] as List)[1]
          ..['projectId'] = 'lead'
          ..['number'] = 12;
        (server.state['conversations'] as List).add({
          ...conversationFixture('empty-lead', 'Lead'),
          'projectId': 'empty',
        });
        final c = server.controller();
        await c.refresh();
        var created = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: grid.buildAppTheme(brightness: Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SuperTabView(
                controller: c,
                app: app,
                onInvite: () {},
                onAddAgent: (_) {},
                onOpenTerminal: (_) {},
                onNewProject: () => created++,
                machineName: (_) => 'Test Mac',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final sidebar = find.byType(ProjectSidebar);
        Finder inside(Finder finder) =>
            find.descendant(of: sidebar, matching: finder);
        final expand = find.byKey(const ValueKey('super-project-expand-lead'));
        final empty = find.byKey(const ValueKey('super-project-expand-empty'));
        expect(expand, findsOneWidget);
        expect(empty, findsOneWidget);
        expect(inside(find.byType(OutlinedButton)), findsNothing);
        expect(inside(find.text('Projects')), findsOneWidget);
        expect(inside(find.text('Machines')), findsOneWidget);

        // Project names always select the lead; disclosure never switches chats.
        await tester.tap(inside(find.text('sample-project')));
        await tester.pumpAndSettle();
        expect(c.selectedId, 'empty-lead');
        await tester.tap(expand);
        await tester.pumpAndSettle();
        expect(c.selectedId, 'empty-lead');
        final work = find.byKey(const ValueKey('super-group-offline'));
        expect(work, findsOneWidget);
        final projectX = tester.getTopLeft(inside(find.text('web-project'))).dx;
        for (final label in ['sample-project', '#12 Offline editing']) {
          expect(tester.getTopLeft(inside(find.text(label))).dx, projectX);
        }
        // Your devices is a heading action beside Add machine, not a row.
        expect(inside(find.text('Your devices')), findsNothing);
        final yourDevices = find.byKey(const ValueKey('super-your-devices'));
        expect(
          find.descendant(of: machinesHeading(), matching: yourDevices),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: yourDevices,
            matching: find.byTooltip('Your devices'),
          ),
          findsOneWidget,
        );
        final projectRect = tester.getRect(
          find.byKey(const ValueKey('super-group-lead')),
        );
        final workRect = tester.getRect(work);
        expect(workRect.left, projectRect.left);
        expect(workRect.right, projectRect.right);

        await tester.tap(work);
        await tester.pumpAndSettle();
        expect(c.selectedId, 'offline');
        await tester.tap(empty);
        await tester.pumpAndSettle();
        expect(c.selectedId, 'offline');
        expect(c.expandedProjects, contains('empty'));
        expect(inside(find.text('No workgroups yet')), findsOneWidget);
        expect(
          tester.getTopLeft(inside(find.text('No workgroups yet'))).dx,
          projectX,
        );
        expect(find.byTooltip('Collapse sample-project'), findsOneWidget);
        expect(
          find.descendant(
            of: empty,
            matching: find.byIcon(AppIcons.chevronDown),
          ),
          findsOneWidget,
        );

        await tester.tap(empty);
        await tester.pumpAndSettle();
        expect(inside(find.text('No workgroups yet')), findsNothing);
        expect(c.selectedId, 'offline');

        // Both navigation actions retain keyboard activation.
        final newProject = find.byTooltip('New project');
        Focus.of(
          tester.element(
            find.descendant(
              of: newProject,
              matching: find.byIcon(AppIcons.plus),
            ),
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(created, 1);
        await tester.tap(find.byKey(const ValueKey('super-your-devices')));
        await tester.pumpAndSettle();
        expect(app.activeSwarm.isDevices, isTrue);
        expect(app.activeSwarm.panes.first.isDevices, isTrue);
        expect(app.activeSwarm.panes.last.isViewer, isFalse);
        expect(app.machinesRequest, isNull);
        final devicesId = app.activeSwarmId;
        await tester.tap(find.byKey(const ValueKey('super-your-devices')));
        await tester.pumpAndSettle();
        expect(app.activeSwarmId, devicesId);
        expect(app.swarms.where((s) => s.isDevices), hasLength(1));
        expect(c.selectedId, 'offline');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await c.flush();
        c.dispose();
      },
    );
  }

  /// A sidebar whose second project has an unread message, so its row draws
  /// the dot the headings' actions line up with.
  Future<SuperTabController> unreadSidebar(ConversationServer server) async {
    server.state['projects'] = [
      projectFixture('lead', 'web-project', 'lead'),
      projectFixture('other', 'other-project', 'other-lead'),
    ];
    (server.state['conversations'] as List).add({
      ...conversationFixture('other-lead', 'Lead'),
      'projectId': 'other',
      'lastMessageSequence': 5,
    });
    final c = server.controller();
    await c.refresh();
    return c;
  }

  Future<void> pumpSidebar(
    WidgetTester tester,
    SuperTabController c,
    AppNotifier app, {
    required double width,
    double scale = 1,
    bool devices = true,
    DateTime Function()? now,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    await tester.pumpWidget(
      MaterialApp(
        theme: grid.buildAppTheme(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: ProjectSidebar(
              controller: c,
              app: app,
              onAddAgent: (_) {},
              needsHuman: (_) => 0,
              onSelect: (_) {},
              onNewProject: () {},
              onYourDevices: devices ? () {} : null,
              now: now ?? DateTime.now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Both headings' + are centered on the column of the project rows' dots,
  /// with Your devices right before the Machines +.
  void expectHeadingActionsAligned(WidgetTester tester, String reason) {
    final dot = tester.getCenter(unreadDot('other-lead')).dx;
    final projectAdd = tester.getRect(find.byTooltip('New project'));
    final machinesAdd = tester.getRect(find.byTooltip('Add machine'));
    expect(projectAdd.center.dx, closeTo(dot, 0.01), reason: reason);
    expect(machinesAdd.center.dx, closeTo(dot, 0.01), reason: reason);
    final devices = tester.getRect(
      find.byKey(const ValueKey('super-your-devices')),
    );
    expect(devices.size, machinesAdd.size, reason: reason);
    expect(devices.center.dy, machinesAdd.center.dy, reason: reason);
    expect(devices.right, closeTo(machinesAdd.left, 0.01), reason: reason);
  }

  testWidgets(
    "both headings' + are centered on the project rows' dot column, with "
    'Your devices just before the Machines +, and no pill while live',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = createApp(connected: true);
      addTearDown(app.dispose);
      final server = ConversationServer();
      final c = await unreadSidebar(server);
      for (final width in [240.0, 420.0]) {
        await pumpSidebar(tester, c, app, width: width);
        final reason = 'at width $width';
        expect(unreadDot('other-lead'), findsOneWidget, reason: reason);
        expectHeadingActionsAligned(tester, reason);
        expect(find.byType(SuperTabMachinesPill), findsNothing, reason: reason);
        expect(find.text('Live'), findsNothing, reason: reason);
      }

      // Hidden when the devices view is unavailable.
      await pumpSidebar(tester, c, app, width: 240, devices: false);
      expect(find.byKey(const ValueKey('super-your-devices')), findsNothing);
      expect(find.byTooltip('Add machine'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await c.flush();
      c.dispose();
    },
  );

  testWidgets(
    'the narrow drawer and minimum pane do not overflow, live or with a wide '
    'reconnecting pill, and the heading actions stay aligned',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = createApp(connected: true);
      addTearDown(app.dispose);
      final server = ConversationServer();
      final c = await unreadSidebar(server);

      for (final unreachable in [false, true]) {
        DateTime Function()? now;
        if (unreachable) {
          server.failReads = true;
          await c.refresh();
          expect(c.backendUnreachable, isTrue);
          // "Reconnecting · 12m" is close to the pill's widest normal content.
          final pinned = c.unreachableSince!.add(const Duration(minutes: 12));
          now = () => pinned;
        }
        for (final width in [180.0, 240.0]) {
          for (final scale in [1.0, 2.0]) {
            await pumpSidebar(
              tester,
              c,
              app,
              width: width,
              scale: scale,
              now: now,
            );
            final reason =
                'at width $width, scale $scale, unreachable $unreachable';
            expect(tester.takeException(), isNull, reason: reason);
            expect(
              find.byType(SuperTabMachinesPill),
              unreachable ? findsOneWidget : findsNothing,
              reason: reason,
            );
            // The minimum pane leaves the pill only its dot, which says the
            // same on hover; anything wider spells it out.
            final words = width >= 240;
            expect(
              find.textContaining('Reconnecting'),
              unreachable && words ? findsOneWidget : findsNothing,
              reason: reason,
            );
            expect(
              find.byTooltip('Reconnecting · 12m'),
              unreachable && !words ? findsOneWidget : findsNothing,
              reason: reason,
            );
            expectHeadingActionsAligned(tester, reason);
            if (unreachable) {
              final pill = tester.getRect(find.byType(SuperTabMachinesPill));
              final devices = tester.getRect(
                find.byKey(const ValueKey('super-your-devices')),
              );
              expect(
                pill.right,
                lessThanOrEqualTo(devices.left),
                reason: reason,
              );
              expect(
                devices.left - pill.right,
                lessThan(20),
                reason: 'the pill sits flush before the actions, $reason',
              );
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await c.flush();
      c.dispose();
    },
  );

  testWidgets('the left Machines group repaints on a live app change alone', (
    tester,
  ) async {
    final app = createApp(connected: true);
    addTearDown(app.dispose);
    final server = ConversationServer();
    server.state['agents'] = [
      {
        'id': 'agent-0',
        'projectId': null,
        'name': 'Lead',
        'displayName': 'Atlas',
        'machineId': 'm',
        'harnessId': 'a0',
        'contributorId': 'owner',
        'configuration': {'engine': 'claude'},
      },
    ];
    final c = server.controller();
    await c.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: grid.buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: ProjectSidebar(
            controller: c,
            app: app,
            onAddAgent: (_) {},
            needsHuman: (_) => 0,
            onSelect: (_) {},
            // This computer reads its own machine; a sample gives the row a
            // non-null age, so its status reflects `connected` immediately.
            readLocal: (_) async => const MachineResources(cpuPercent: 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Let the first local read land.
    await tester.pump();
    await tester.pump();
    Finder statusDot() => find.descendant(
      of: find.byKey(const ValueKey('super-machine-m')),
      matching: find.byType(SuperTabMachineDot),
    );
    expect(
      tester.widget<SuperTabMachineDot>(statusDot()).status,
      isNot(SuperTabMachineStatus.offline),
    );

    // The Machines group has no listener of its own on the controller the
    // rest of this sidebar rebuilds on, so a bare app event (no controller
    // change, no re-pump) must still repaint it.
    await app.handleEventForTest('m', {'type': 'node_status', 'online': false});
    await tester.pump();
    expect(
      tester.widget<SuperTabMachineDot>(statusDot()).status,
      SuperTabMachineStatus.offline,
    );

    await tester.pumpWidget(const SizedBox());
    await c.flush();
    c.dispose();
  });

  testWidgets('Projects and Machines groups collapse and persist', (
    tester,
  ) async {
    final app = createApp(connected: true);
    addTearDown(app.dispose);
    final server = ConversationServer();
    server.state['projects'] = [projectFixture('lead', 'web-project', 'lead')];
    final c = server.controller();
    await c.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: grid.buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: SuperTabView(
            controller: c,
            app: app,
            onInvite: () {},
            onAddAgent: (_) {},
            onOpenTerminal: (_) {},
            onNewProject: () {},
            machineName: (_) => 'Test Mac',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sidebar = find.byType(ProjectSidebar);
    Finder inside(Finder finder) =>
        find.descendant(of: sidebar, matching: finder);

    const machinesBody = 'Add a machine for the product manager to use.';
    final yourDevices = find.byKey(const ValueKey('super-your-devices'));
    expect(inside(find.text('web-project')), findsOneWidget);
    expect(inside(find.text(machinesBody)), findsOneWidget);
    expect(inside(yourDevices), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse Projects'));
    await tester.pumpAndSettle();
    expect(inside(find.text('web-project')), findsNothing);
    expect(c.projectsGroupOpen, isFalse);

    await tester.tap(find.byTooltip('Collapse Machines'));
    await tester.pumpAndSettle();
    expect(inside(find.text(machinesBody)), findsNothing);
    // A heading action, so it stays reachable while the group is collapsed.
    expect(inside(yourDevices), findsOneWidget);
    expect(c.machinesGroupOpen, isFalse);

    // Persisted state survives a restart of the sidebar's controller.
    await c.flush();
    final saved = server.saved!;
    expect(saved['projectsGroupOpen'], isFalse);
    expect(saved['machinesGroupOpen'], isFalse);
    final reopened = server.controller(initial: saved);
    await reopened.refresh();
    expect(reopened.projectsGroupOpen, isFalse);
    expect(reopened.machinesGroupOpen, isFalse);

    await tester.tap(find.byTooltip('Expand Projects'));
    await tester.pumpAndSettle();
    expect(inside(find.text('web-project')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await c.flush();
    c.dispose();
    await reopened.flush();
    reopened.dispose();
  });
}
