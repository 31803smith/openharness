import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shared/widgets/app_choice_picker.dart';
import 'package:harness/shared/widgets/app_select_field.dart';

void main() {
  testWidgets('tiled dropdown focus does not mark a second choice', (
    tester,
  ) async {
    var selected = 'codex';
    const moreKey = ValueKey('more');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppChoicePicker<String>(
              value: selected,
              options: const [
                SelectOption(value: 'codex', label: 'Codex'),
                SelectOption(value: 'claude', label: 'Claude Code'),
                SelectOption(value: 'opencode', label: 'OpenCode'),
                SelectOption(value: 'amp', label: 'Amp'),
              ],
              optionKey: (id) => ValueKey(id),
              moreKey: moreKey,
              moreLabel: 'More engines',
              tileSize: const Size(180, 76),
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );
    Future<void> chooseFromMenu(LogicalKeyboardKey key, String letter) async {
      await tester.tap(find.byKey(moreKey));
      await tester.sendKeyEvent(key, character: letter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    await chooseFromMenu(LogicalKeyboardKey.keyA, 'a');
    expect(selected, 'amp');
    expect(
      tester.widget<AppSelectField<String>>(find.byKey(moreKey)).selected,
      isTrue,
    );
    expect(
      tester
          .widgetList<AppChoiceTile>(find.byType(AppChoiceTile))
          .where((tile) => tile.selected),
      isEmpty,
    );

    // Picking a primary choice from the menu returns focus to the fourth tile.
    await chooseFromMenu(LogicalKeyboardKey.keyC, 'c');
    expect(selected, 'codex');
    expect(find.text('Amp'), findsOneWidget);
    final more = find.byKey(moreKey);
    final trigger = tester.widget<InkWell>(
      find.descendant(of: more, matching: find.byType(InkWell)).first,
    );
    expect(trigger.focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.widget<AppSelectField<String>>(more).selected, isFalse);
    final container = tester.widget<AnimatedContainer>(
      find.descendant(of: more, matching: find.byType(AnimatedContainer)).first,
    );
    expect(
      ((container.decoration! as BoxDecoration).border! as Border).top.color,
      Colors.transparent,
    );
    expect(
      tester
          .widgetList<AppChoiceTile>(find.byType(AppChoiceTile))
          .where((tile) => tile.selected)
          .map((tile) => tile.label),
      ['Codex'],
    );
  });

  testWidgets(
    'overflow selection replaces the third choice and retains keyboard control',
    (tester) async {
      var selected = 'local';
      final changes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 520,
                child: StatefulBuilder(
                  builder: (context, setState) => AppChoicePicker<String>(
                    value: selected,
                    options: const [
                      SelectOption(
                        value: 'local',
                        label: 'M2',
                        detail: 'This computer',
                      ),
                      SelectOption(
                        value: 'office',
                        label: 'Office',
                        detail: 'Remote',
                      ),
                      SelectOption(
                        value: 'home',
                        label: 'Home',
                        detail: 'Remote · Offline',
                      ),
                      SelectOption(
                        value: 'studio',
                        label: 'Studio',
                        detail: 'Remote',
                      ),
                    ],
                    showDetails: true,
                    optionKey: (id) => ValueKey(id),
                    moreKey: const ValueKey('more'),
                    moreLabel: 'More machines',
                    onChanged: (value) => setState(() {
                      selected = value;
                      changes.add(value);
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(TextButton), findsNWidgets(3));
      expect(find.text('Remote · Offline'), findsOneWidget);
      expect(find.text('Studio'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('local')));
      expect(changes, isEmpty);
      await tester.tap(find.byKey(const ValueKey('more')));
      // Type immediately, before the first menu frame.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, ['studio']);
      expect(find.byType(TextButton), findsNWidgets(3));
      expect(find.text('Home'), findsNothing);
      expect(find.text('Studio'), findsOneWidget);
      final overflowFocus = tester
          .widget<InkWell>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('more')),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .focusNode!;
      expect(overflowFocus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(changes, ['studio']);
      expect(overflowFocus.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('up to three options need no overflow menu', (tester) async {
    for (var count = 1; count <= 3; count++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppChoicePicker<int>(
              value: 0,
              options: [
                for (var i = 0; i < count; i++)
                  SelectOption(value: i, label: 'Machine $i'),
              ],
              optionKey: (id) => ValueKey(id),
              moreLabel: 'More machines',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(TextButton), findsNWidgets(count));
      expect(find.byType(AppSelectField<int>), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
