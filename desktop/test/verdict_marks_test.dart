// The verdict's phases: parsed defensively from the frame, drawn as a strip
// beside the chip in the viewer pane's header.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/theme/app_theme.dart';
import 'package:harness/widgets/verdict_marks.dart';

void main() {
  test('phases parse in order, defaulting and dropping what is malformed', () {
    final verdict = AgentVerdict.fromJson({
      'ready': false,
      'phases': [
        {'id': 'build', 'name': 'Build', 'state': 'done', 'artifact': 'a.step'},
        {'name': 'Checks', 'state': 'active'},
        {'name': 'Fab', 'state': 'someday'},
        {'name': '', 'state': 'done'},
        'nope',
        {'id': 'x', 'state': 'done'},
      ],
    })!;
    expect(verdict.phases.map((p) => p.name), ['Build', 'Checks', 'Fab']);
    expect(verdict.phases.map((p) => p.state), [
      AgentPhaseState.done,
      AgentPhaseState.active,
      AgentPhaseState.pending,
    ]);
    expect(verdict.phases.first.artifact, 'a.step');
    expect(verdict.phases[1].id, 'checks');
    expect(verdict.activePhase?.name, 'Checks');
    expect(AgentVerdict.fromJson({'ready': true})!.phases, isEmpty);
    expect(
      AgentVerdict.fromJson({'ready': true, 'phases': 'x'})!.phases,
      isEmpty,
    );
    final many = AgentVerdict.fromJson({
      'ready': true,
      'phases': [
        for (var i = 0; i < 20; i++) {'name': 'P$i'},
      ],
    })!;
    expect(many.phases, hasLength(12));
  });

  testWidgets('the strip names every phase and says which is under way', (
    tester,
  ) async {
    const phases = [
      AgentPhase(id: 'outline', name: 'Outline', state: AgentPhaseState.done),
      AgentPhase(id: 'draft', name: 'Draft', state: AgentPhaseState.active),
      AgentPhase(id: 'polish', name: 'Polish'),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: PhaseStrip(phases: phases)),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('pane-phase-strip')), findsOneWidget);
    expect(find.text('Outline'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Polish'), findsOneWidget);
  });

  testWidgets('the chip says ready, or how far from it', (tester) async {
    final chip = find.byKey(const ValueKey('pane-verdict-chip'));
    final cases = <(AgentVerdict, String, Color)>[
      (
        const AgentVerdict(ready: true, summary: 'Board is fab-ready'),
        'Ready',
        AppColors.success,
      ),
      (
        const AgentVerdict(ready: false, errors: 3, warnings: 2),
        '3 errors',
        AppColors.danger,
      ),
      (
        const AgentVerdict(ready: false, errors: 0, warnings: 1),
        '1 warning',
        AppColors.warning,
      ),
      (const AgentVerdict(ready: false), 'Checked', AppColors.mutedStrong),
    ];
    for (final (verdict, label, color) in cases) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VerdictChip(verdict: verdict)),
        ),
      );
      expect(chip, findsOneWidget, reason: label);
      expect(
        find.descendant(of: chip, matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.descendant(of: chip, matching: find.text(label)))
            .style
            ?.color,
        color,
      );
      if (verdict.summary != null) {
        expect(find.byTooltip(verdict.summary!), findsOneWidget);
      }
    }
  });
}
