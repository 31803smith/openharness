import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/pane_arrangement.dart';
import 'package:harness/state/pane_preset.dart';

void main() {
  test(
    'all preset dividers preserve coverage and avoid overlaps at either limit',
    () {
      for (var count = 2; count <= 16; count++) {
        for (final preset in PanePreset.forCount(count)) {
          final layout = PaneArrangement(preset.tilesFor(count));
          final area = layout.tiles.fold<double>(
            0,
            (sum, tile) => sum + tile.width * tile.height,
          );
          for (final divider in layout.dividers) {
            for (final position in [-2.0, 2.0]) {
              final moved = layout.resize(
                divider,
                position,
                minimum: const Size(.08, .08),
              );
              expect(
                PaneArrangement.fromJson(moved.toJson()),
                isNotNull,
                reason: '$count ${preset.name} ${divider.id}',
              );
              expect(
                moved.tiles.fold<double>(
                  0,
                  (sum, tile) => sum + tile.width * tile.height,
                ),
                closeTo(area, .000001),
              );
              for (var i = 0; i < count; i++) {
                expect(
                  moved.tiles[i].width,
                  greaterThanOrEqualTo(
                    layout.tiles[i].width.clamp(0, .08) - .000001,
                  ),
                );
                expect(
                  moved.tiles[i].height,
                  greaterThanOrEqualTo(
                    layout.tiles[i].height.clamp(0, .08) - .000001,
                  ),
                );
              }
            }
          }
        }
      }
    },
  );

  test('connected grid dividers stay aligned while separate side stacks resize independently', () {
    final quad = PaneArrangement(PanePreset.quad.tilesFor(4));
    expect(quad.dividers.length, 2);
    final vertical = quad.dividers.singleWhere(
      (d) => d.axis == PaneResizeAxis.x,
    );
    final resized = quad.resize(vertical, .6, minimum: const Size(.1, .1));
    expect(resized.tiles[0].right, .6);
    expect(resized.tiles[2].right, .6);
    final sides = PaneArrangement(PanePreset.middleMain.tilesFor(5));
    expect(sides.dividers.length, 4);
    final left = sides.dividers.singleWhere(
      (d) => d.axis == PaneResizeAxis.y && d.before.contains(0),
    );
    final changed = sides.resize(left, .65, minimum: const Size(.1, .1));
    expect(changed.tiles[0].bottom, .65);
    expect(changed.tiles[3].top, .65);
    for (final untouched in [1, 2, 4]) {
      expect(changed.tiles[untouched], sides.tiles[untouched]);
    }
  });

  test('saved sizes reject malformed, overlapping and non-finite geometry', () {
    for (final raw in [
      null,
      {},
      [],
      [
        [0, 0, 1, 1],
      ],
      [
        [0, 0, .8, 1],
        [.7, 0, 1, 1],
      ],
      [
        [0, 0, double.nan, 1],
        [.5, 0, 1, 1],
      ],
      [
        [0, 0, .5, 1],
        [.5, 0, double.infinity, 1],
      ],
      [
        [0, 0, 0, 1],
        [.5, 0, 1, 1],
      ],
    ]) {
      expect(PaneArrangement.fromJson(raw), isNull);
    }
    final valid = PaneArrangement(PanePreset.columns.tilesFor(2)).toJson();
    expect(
      PaneArrangement.readSaved({'2:columns:0:columns': valid, '3:bad': valid})
          .keys,
      ['2:columns:0:columns'],
    );
  });
}
