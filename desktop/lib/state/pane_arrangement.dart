import 'dart:math' as math;
import 'dart:ui';

enum PaneResizeAxis { x, y }

/// Normalized rectangles preserve the preset's topology while its dividers
/// move. They describe slots, not sessions, so moving agents keeps their sizes.
class PaneArrangement {
  PaneArrangement(Iterable<Rect> tiles) : tiles = List.unmodifiable(tiles);
  final List<Rect> tiles;
  static const _epsilon = 0.000001;

  late final List<PaneDivider> dividers = _findDividers();

  List<PaneDivider> _findDividers() {
    final segments =
        <({PaneResizeAxis axis, double at, double start, double end})>[];
    for (final a in tiles) {
      for (final b in tiles) {
        final top = math.max(a.top, b.top);
        final bottom = math.min(a.bottom, b.bottom);
        if ((a.right - b.left).abs() < _epsilon && bottom - top > _epsilon) {
          segments.add((
            axis: PaneResizeAxis.x,
            at: a.right,
            start: top,
            end: bottom,
          ));
        }
        final left = math.max(a.left, b.left);
        final right = math.min(a.right, b.right);
        if ((a.bottom - b.top).abs() < _epsilon && right - left > _epsilon) {
          segments.add((
            axis: PaneResizeAxis.y,
            at: a.bottom,
            start: left,
            end: right,
          ));
        }
      }
    }
    segments.sort((a, b) {
      final axis = a.axis.index.compareTo(b.axis.index);
      if (axis != 0) return axis;
      final at = a.at.compareTo(b.at);
      return at != 0 ? at : a.start.compareTo(b.start);
    });
    final merged =
        <({PaneResizeAxis axis, double at, double start, double end})>[];
    for (final segment in segments) {
      if (merged.isNotEmpty) {
        final previous = merged.last;
        if (segment.axis == previous.axis &&
            (segment.at - previous.at).abs() < _epsilon &&
            segment.start <= previous.end + _epsilon) {
          merged[merged.length - 1] = (
            axis: previous.axis,
            at: previous.at,
            start: previous.start,
            end: math.max(previous.end, segment.end),
          );
          continue;
        }
      }
      merged.add(segment);
    }
    return List.unmodifiable([
      for (final segment in merged)
        PaneDivider(
          axis: segment.axis,
          position: segment.at,
          start: segment.start,
          end: segment.end,
          before: [
            for (var i = 0; i < tiles.length; i++)
              if (_touches(
                tiles[i],
                segment.axis,
                segment.at,
                segment.start,
                segment.end,
                before: true,
              ))
                i,
          ],
          after: [
            for (var i = 0; i < tiles.length; i++)
              if (_touches(
                tiles[i],
                segment.axis,
                segment.at,
                segment.start,
                segment.end,
                before: false,
              ))
                i,
          ],
        ),
    ]);
  }

  static bool _touches(
    Rect tile,
    PaneResizeAxis axis,
    double at,
    double start,
    double end, {
    required bool before,
  }) {
    final edge = axis == PaneResizeAxis.x
        ? before
              ? tile.right
              : tile.left
        : before
        ? tile.bottom
        : tile.top;
    final from = axis == PaneResizeAxis.x ? tile.top : tile.left;
    final to = axis == PaneResizeAxis.x ? tile.bottom : tile.right;
    return (edge - at).abs() < _epsilon &&
        math.min(end, to) - math.max(start, from) > _epsilon;
  }

  PaneArrangement resize(
    PaneDivider divider,
    double position, {
    required Size minimum,
  }) {
    if (!position.isFinite || divider.before.isEmpty || divider.after.isEmpty) {
      return this;
    }
    final horizontal = divider.axis == PaneResizeAxis.x;
    final floor = horizontal ? minimum.width : minimum.height;
    if (!floor.isFinite || floor < 0) return this;
    // A deliberately dense preset may already be below the normal floor.
    // Resizing can improve that tile, but cannot make it smaller than it was.
    final lower = divider.before
        .map((i) {
          final tile = tiles[i];
          return horizontal
              ? tile.left + math.min(floor, tile.width)
              : tile.top + math.min(floor, tile.height);
        })
        .reduce(math.max);
    final upper = divider.after
        .map((i) {
          final tile = tiles[i];
          return horizontal
              ? tile.right - math.min(floor, tile.width)
              : tile.bottom - math.min(floor, tile.height);
        })
        .reduce(math.min);
    if (lower > upper + _epsilon) return this;
    final next = position.clamp(lower, math.max(lower, upper)).toDouble();
    if ((next - divider.position).abs() < _epsilon) return this;
    final before = divider.before.toSet(), after = divider.after.toSet();
    return PaneArrangement([
      for (var i = 0; i < tiles.length; i++)
        Rect.fromLTRB(
          horizontal && after.contains(i) ? next : tiles[i].left,
          !horizontal && after.contains(i) ? next : tiles[i].top,
          horizontal && before.contains(i) ? next : tiles[i].right,
          !horizontal && before.contains(i) ? next : tiles[i].bottom,
        ),
    ]);
  }

  double balancedPosition(PaneDivider divider) {
    final x = divider.axis == PaneResizeAxis.x;
    final start = divider.before
        .map((i) => x ? tiles[i].left : tiles[i].top)
        .reduce(math.max);
    final end = divider.after
        .map((i) => x ? tiles[i].right : tiles[i].bottom)
        .reduce(math.min);
    return (start + end) / 2;
  }

  List<List<double>> toJson() => [
    for (final tile in tiles) [tile.left, tile.top, tile.right, tile.bottom],
  ];

  static PaneArrangement? fromJson(Object? value) {
    if (value is! List || value.length < 2 || value.length > 64) return null;
    final tiles = <Rect>[];
    for (final item in value) {
      if (item is! List ||
          item.length != 4 ||
          item.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
        return null;
      }
      final numbers = item.cast<num>().map((v) => v.toDouble()).toList();
      final rect = Rect.fromLTRB(
        numbers[0],
        numbers[1],
        numbers[2],
        numbers[3],
      );
      if (rect.width < _epsilon ||
          rect.height < _epsilon ||
          tiles.any((tile) {
            final overlap = tile.intersect(rect);
            return overlap.width > _epsilon && overlap.height > _epsilon;
          })) {
        return null;
      }
      tiles.add(rect);
    }
    return PaneArrangement(tiles);
  }

  static Map<String, PaneArrangement> readSaved(Object? value) {
    if (value is! Map) return {};
    final result = <String, PaneArrangement>{};
    for (final entry in value.entries.take(64)) {
      final key = entry.key;
      if (key is! String || key.length > 80) continue;
      final count = int.tryParse(key.split(':').first);
      final arrangement = fromJson(entry.value);
      if (arrangement != null && count == arrangement.tiles.length) {
        result[key] = arrangement;
      }
    }
    return result;
  }
}

class PaneDivider {
  PaneDivider({
    required this.axis,
    required this.position,
    required this.start,
    required this.end,
    required List<int> before,
    required List<int> after,
  }) : before = List.unmodifiable(before),
       after = List.unmodifiable(after);
  final PaneResizeAxis axis;
  final double position, start, end;
  final List<int> before, after;
  String get id => '${axis.name}:${before.join(',')}:${after.join(',')}';
  bool touches(int tile) => before.contains(tile) || after.contains(tile);
}
