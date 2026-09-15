import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pane_layout_store.dart';
import 'package:harness/state/pane_preset.dart';

import 'swarm_state_test.dart' show createApp, MemoryStore;

String _shape(List<Rect> tiles) {
  final coordinates = [
    for (final tile in tiles)
      [
        tile.left,
        tile.top,
        tile.right,
        tile.bottom,
      ].map((value) => value.toStringAsFixed(8)).join(','),
  ]..sort();
  return coordinates.join(';');
}

void main() {
  test('saved automatic and regular grids remain restorable', () async {
    final storage = MemoryStore();
    final presets = {
      2: PanePreset.splitLong,
      5: PanePreset.cols2,
      6: PanePreset.auto,
      7: PanePreset.cols3,
      8: PanePreset.cols4,
      9: PanePreset.cols5,
    };
    storage.values['terminal_pane_presets'] = jsonEncode({
      for (final entry in presets.entries) '${entry.key}': entry.value.id,
    });
    expect(await PaneLayoutStore(storage: storage).loadPresets(), presets);

    final app = createApp(store: storage);
    await app.addAgentToSwarm('m', 'a0');
    app.activeSwarm.presets.addAll(presets);
    app.renameSwarm(app.activeSwarmId, 'Saved layouts');
    await Future<void>.delayed(Duration.zero);
    final restored = createApp(store: storage);
    await restored.restorePaneLayoutForTest();
    expect(restored.activeSwarm.presets, presets);
    app.dispose();
    restored.dispose();
  });

  test('two panes offer just side-by-side and stacked', () {
    expect(PanePreset.forCount(2), [PanePreset.columns, PanePreset.rows]);
  });

  test(
    'every pane count offers distinct arrangements, not automatic aliases',
    () {
      for (var count = 2; count <= AppNotifier.maxPanes; count++) {
        final seen = <String, PanePreset>{};
        final labels = <String>{};
        for (final preset in PanePreset.forCount(count)) {
          final key = _shape(preset.tilesFor(count));
          expect(
            seen[key],
            isNull,
            reason: '$count panes: ${preset.id} duplicates ${seen[key]?.id}',
          );
          expect(
            labels.add(preset.label),
            isTrue,
            reason: '$count ${preset.label}',
          );
          expect(preset, isNot(PanePreset.auto));
          expect(preset, isNot(PanePreset.splitLong));
          seen[key] = preset;
        }
        expect(seen.length, inInclusiveRange(2, 6), reason: '$count panes');
      }
    },
  );

  test(
    'every offered arrangement fills the canvas with nonoverlapping panes',
    () {
      for (var count = 2; count <= AppNotifier.maxPanes; count++) {
        for (final preset in PanePreset.forCount(count)) {
          final tiles = preset.tilesFor(count);
          final reason = '$count panes: ${preset.id}';
          expect(tiles, hasLength(count), reason: reason);
          var area = 0.0;
          for (var i = 0; i < tiles.length; i++) {
            final tile = tiles[i];
            expect(tile.width, greaterThan(0), reason: reason);
            expect(tile.height, greaterThan(0), reason: reason);
            expect(tile.left, greaterThanOrEqualTo(0), reason: reason);
            expect(tile.top, greaterThanOrEqualTo(0), reason: reason);
            expect(tile.right, lessThanOrEqualTo(1), reason: reason);
            expect(tile.bottom, lessThanOrEqualTo(1), reason: reason);
            area += tile.width * tile.height;
            for (final other in tiles.skip(i + 1)) {
              expect(tile.overlaps(other), isFalse, reason: reason);
            }
          }
          expect(area, closeTo(1, 1e-9), reason: reason);
        }
      }
    },
  );
}
