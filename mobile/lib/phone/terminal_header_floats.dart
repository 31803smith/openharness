import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';

/// One of the things the header held, as a floating button.
class TerminalHeaderChoice {
  const TerminalHeaderChoice({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;

  /// For screen readers and the long-press tooltip. The buttons carry no words
  /// of their own — three marks in a column, in the order they sat in the row
  /// they came out of, is what makes them readable.
  final String label;

  final VoidCallback onTap;
}

/// The header's controls, floating down the right edge once the row itself has
/// scrolled away.
///
/// ⚠️ **Three buttons, not one that opens three.** A single button folding the
/// lot away was tried first: it put the page's only search and its only actions
/// menu behind a tap and a fan, which is two gestures to reach what had been
/// one. These stay in the order they had in the header — search, new, actions —
/// so the column reads as that row stood on its end.
///
/// ⚠️ **Each one flies out of its own place in the header.** The row's search
/// bar, `+` and `⋯` are at known points across the top of the screen, and each
/// button travels from its own to its place in this column. A set that simply
/// faded in would say nothing about where the header went, which was the
/// complaint that produced this file.
class TerminalHeaderFloats extends StatelessWidget {
  const TerminalHeaderFloats({
    super.key,
    required this.choices,
    required this.progress,
    required this.origins,
  });

  final List<TerminalHeaderChoice> choices;

  /// 0 the header is in place and these are nowhere, 1 fully arrived.
  final Animation<double> progress;

  /// Where each button starts, relative to its resting place in the column.
  ///
  /// ⚠️ Given by the page, not worked out here. The origins are points in the
  /// header's own row, and that row's layout is the page's business — this
  /// widget knows only how to fly something from A to B.
  final List<Offset> origins;

  /// A button's diameter, and the gap from one to the next.
  ///
  /// ⚠️ **Smaller than the mic, and that is the right way round.** The mic is
  /// the page's one action and is held through a whole sentence; these are
  /// chrome that scrolling put here, tapped once and rarely. Sizing them to
  /// match made three circles compete with the output they float over.
  ///
  /// ⚠️ 32 is a floor. [touchExtent] is what a finger actually gets — the
  /// circles are drawn small and hit large, so shrinking them further would cost
  /// legibility without buying the terminal anything.
  static const double extent = 32;
  static const double pitch = 40;

  /// What the finger may land on, against the [extent] that is drawn.
  ///
  /// ⚠️ **Capped at [pitch], and it must not exceed it.** The targets are drawn
  /// small and hit large, but two that overlap would hand the shared band to
  /// whichever is painted later — the lower button, since the column builds top
  /// down — so a tap aimed just under Search would open New agent. Matching the
  /// pitch is what makes the targets meet exactly and leave no dead glass
  /// between them either.
  static const double touchExtent = pitch;

  /// How far the column sits from the screen's top and right edges.
  static const double inset = 10;

  /// What a column of [count] buttons is tall.
  static double heightFor(int count) =>
      count == 0 ? 0 : (count - 1) * pitch + extent;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return SizedBox(
      width: extent,
      height: heightFor(choices.length),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (index, choice) in choices.indexed)
            Positioned(
              top: index * pitch,
              right: 0,
              child: _Float(
                progress: progress,
                // ⚠️ Staggered from the top down, in the order they left the
                // header. Arriving together reads as a menu appearing; one after
                // another reads as the row coming apart.
                delay: index * 0.1,
                origin: index < origins.length ? origins[index] : Offset.zero,
                choice: choice,
              ),
            ),
        ],
      ),
    );
  }
}

/// One button, travelling from where it sat in the header to where it floats.
class _Float extends StatelessWidget {
  const _Float({
    required this.progress,
    required this.delay,
    required this.origin,
    required this.choice,
  });

  final Animation<double> progress;

  /// How far into the run this one starts, 0 to 1.
  final double delay;

  /// Where it comes from, relative to where it ends up.
  final Offset origin;

  final TerminalHeaderChoice choice;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return AnimatedBuilder(
      animation: progress,
      // Built once: what moves is the transform around it.
      child: _Button(choice: choice),
      builder: (context, child) {
        // ⚠️ The stagger comes off the shared VALUE rather than from a timer of
        // its own. One clock keeps the three in step when a scroll reverses
        // part-way through; separate controllers would each be somewhere
        // different when the reverse began, and they would land untidily.
        final t = ((progress.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (t == 0) return const SizedBox.shrink();
        return Transform.translate(
          offset: Offset(origin.dx * (1 - t), origin.dy * (1 - t)),
          child: Opacity(
            // ⚠️ Fades in over the FIRST part of the journey only. A button
            // still translucent as it lands looks like it failed to arrive — and
            // the header it came from is fading over the same stretch, so two
            // half-transparent things in one place would read as a smear.
            opacity: (t / 0.6).clamp(0.0, 1.0),
            child: Transform.scale(scale: lerpDouble(0.55, 1, t), child: child),
          ),
        );
      },
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.choice});

  final TerminalHeaderChoice choice;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Semantics(
      button: true,
      label: choice.label,
      child: Tooltip(
        message: choice.label,
        // ⚠️ The target is the OUTER box and the circle is drawn inside it: the
        // visible button is 32pt, which is under what a thumb wants, and an
        // [OverflowBox] is what lets the hit area exceed the slot the column
        // lays out without pushing the circles apart.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: choice.onTap,
          child: SizedBox.square(
            dimension: TerminalHeaderFloats.extent,
            child: OverflowBox(
              maxWidth: TerminalHeaderFloats.touchExtent,
              maxHeight: TerminalHeaderFloats.touchExtent,
              child: SizedBox.square(
                dimension: TerminalHeaderFloats.touchExtent,
                child: Center(
                  child: Container(
                    width: TerminalHeaderFloats.extent,
                    height: TerminalHeaderFloats.extent,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppGlass.surfaceFill,
                      border: Border.all(color: AppGlass.lift),
                      // ⚠️ A shadow, because these float over streaming output rather
                      // than over a surface. Without one the circle's edge disappears
                      // wherever a bright line runs under it.
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      choice.icon,
                      size: 15,
                      color: AppPalette.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
