import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import 'engine_identity.dart';

/// The ground behind the empty new-swarm canvas (mockup/swarm-background.html,
/// "9 · Aurora mesh").
///
/// It used to be a photograph — a lake at dusk under a gradient — and it was
/// the one surface in the app with a subject. Every other screen stands on the
/// same near-black panel with Geist on it; that one said "mountains", warmed
/// the white headline orange at the top, and made the accent button compete
/// with a sunset. A ground should be a ground.
///
/// This is the panel colour with three very dim washes at the corners, in the
/// three colours the app already owns — the accent, and the marks Claude and
/// Codex wear in the rail — meeting in the middle as plain ground. Each stays
/// under 15%, which is what keeps it a tinted room rather than a poster, and
/// what keeps the New agent button the only real blue on screen. Drawn, not
/// scaled, so it holds at any window size and costs no asset.
class SwarmWallpaper extends StatelessWidget {
  const SwarmWallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Lighter in light mode: a wash that reads as a tint on charcoal reads as
    // a stain on white.
    final strength = grid.AppTheme.pick(0.6, 1.0);
    return CustomPaint(
      painter: _MeshPainter(
        ground: grid.AppPalette.panelBg,
        washes: [
          // Not [grid.AppPalette.swarmAccent]: in the graphite palette that is
          // #bdcbdc, a pale grey-blue made to be TEXT on charcoal, and as a wash
          // it reads as a smudge. This is the blue the mockup was drawn in — the
          // blue the New agent button and the Codex mark already share a family
          // with — and it is only ever seen at 14%.
          _Wash(
            const Color(0xFF6E8BFF),
            0.14 * strength,
            const Alignment(-0.7, -0.5),
            0.40,
            0.50,
          ),
          _Wash(
            engineIdentity('claude').color,
            0.10 * strength,
            const Alignment(0.7, -0.7),
            0.45,
            0.40,
          ),
          _Wash(
            engineIdentity('codex').color,
            0.08 * strength,
            const Alignment(0.2, 0.9),
            0.50,
            0.45,
          ),
        ],
      ),
      size: Size.infinite,
    );
  }
}

/// One wash: a radial fade from `opacity` at `at` to nothing, `rx`/`ry` wide
/// and tall as fractions of the canvas — the CSS
/// `radial-gradient(ellipse rx ry at …)` the mockup was drawn with.
class _Wash {
  const _Wash(this.color, this.opacity, this.at, this.rx, this.ry);
  final Color color;
  final double opacity;
  final Alignment at;
  final double rx, ry;
}

class _MeshPainter extends CustomPainter {
  const _MeshPainter({required this.ground, required this.washes});
  final Color ground;
  final List<_Wash> washes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    for (final w in washes) {
      final c = at(w.at, size);
      final rx = size.width * w.rx, ry = size.height * w.ry;
      // A circle of radius rx, squashed to ry vertically about its centre:
      // the shader's own transform, so the fade itself is elliptical rather
      // than a circle drawn in an oval.
      final m = Matrix4.identity()
        ..translateByDouble(c.dx, c.dy, 0, 1)
        ..scaleByDouble(1, ry / rx, 1, 1)
        ..translateByDouble(-c.dx, -c.dy, 0, 1);
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          c,
          rx,
          [w.color.withValues(alpha: w.opacity), w.color.withValues(alpha: 0)],
          const [0.0, 0.7],
          TileMode.clamp,
          m.storage,
        );
      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  static Offset at(Alignment a, Size s) =>
      Offset(s.width * (a.x + 1) / 2, s.height * (a.y + 1) / 2);

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.ground != ground ||
      old.washes.length != washes.length ||
      Iterable.generate(washes.length).any(
        (i) =>
            old.washes[i].color != washes[i].color ||
            old.washes[i].opacity != washes[i].opacity,
      );
}
