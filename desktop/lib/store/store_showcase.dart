import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/dsh_catalog.dart';
import '../core/test_run.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_icon_button.dart';
import '../widgets/engine_identity.dart';

/// The product page's centrepiece: what you ask, and what the harness makes of it.
///
/// A store page that lists features tells a person what a harness is; this shows them what it does.
/// One example at a time fills a stage — the prompt types itself out on the left, a line sweeps
/// across while the harness "works", and the picture of the real output settles in on the right —
/// then the next example follows. A strip under the stage picks one directly, and "Try this prompt"
/// opens New Harness with that prompt as its first message, so the thing that made someone lean in is
/// one click from happening on their own machine.
///
/// Reduce Motion (and `flutter test`) shows each example whole and does not advance on its own.
class StoreShowcase extends StatefulWidget {
  const StoreShowcase({
    super.key,
    required this.entry,
    required this.examples,
    this.onTry,
    this.autoAdvance,
  });

  final DshEntry entry;
  final List<StoreExample> examples;

  /// Opens New Harness with the prompt; null when there is no machine to open it on.
  final ValueChanged<String>? onTry;

  /// Types, reveals and moves on to the next example; off under `flutter test` unless asked for.
  final bool? autoAdvance;

  @override
  State<StoreShowcase> createState() => _StoreShowcaseState();
}

class _StoreShowcaseState extends State<StoreShowcase>
    with TickerProviderStateMixin {
  static const _dwell = Duration(seconds: 7);

  late final AnimationController _type = AnimationController(vsync: this);
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _dwellClock = AnimationController(
    vsync: this,
    duration: _dwell,
  );
  var _index = 0;
  var _hovering = false;

  bool get _animate =>
      (widget.autoAdvance ?? !kUnderTest) &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  StoreExample get _example => widget.examples[_index];

  @override
  void initState() {
    super.initState();
    _type.addStatusListener((status) {
      if (status == AnimationStatus.completed) _reveal.forward(from: 0);
    });
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && _animate && !_hovering) {
        _dwellClock.forward(from: 0);
      }
    });
    _dwellClock.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _select((_index + 1) % widget.examples.length);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play();
    });
  }

  @override
  void didUpdateWidget(StoreShowcase old) {
    super.didUpdateWidget(old);
    if (_index >= widget.examples.length) _select(0);
  }

  @override
  void dispose() {
    _type.dispose();
    _reveal.dispose();
    _dwellClock.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _index = index);
    _play();
  }

  /// Type the prompt, then reveal the output; shown whole at once when nothing may move.
  void _play() {
    _dwellClock.stop();
    _dwellClock.value = 0;
    if (!_animate) {
      _type.value = 1;
      _reveal.value = 1;
      return;
    }
    final chars = _example.prompt.length;
    _type.duration = Duration(milliseconds: (chars * 22).clamp(600, 2600));
    _reveal.value = 0;
    _type.forward(from: 0);
  }

  void _hover(bool hovering) {
    _hovering = hovering;
    if (!_animate) return;
    if (hovering) {
      _dwellClock.stop();
    } else if (_reveal.isCompleted) {
      _dwellClock.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    if (widget.examples.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final prompt = _PromptPane(
          entry: widget.entry,
          example: _example,
          typing: _type,
          large: wide,
          onTry: widget.onTry,
        );
        final output = _OutputPane(
          entry: widget.entry,
          example: _example,
          typing: _type,
          reveal: _reveal,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MouseRegion(
              onEnter: (_) => _hover(true),
              onExit: (_) => _hover(false),
              child: Container(
                key: const ValueKey('store-showcase-stage'),
                padding: EdgeInsets.all(wide ? 28 : 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      grid.AppPalette.cardBg,
                      Color.alphaBlend(
                        grid.AppPalette.accent.withValues(alpha: 0.10),
                        grid.AppPalette.cardBg,
                      ),
                    ],
                  ),
                  border: Border.all(color: grid.AppPalette.divider),
                ),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: constraints.maxWidth * 0.34,
                            child: prompt,
                          ),
                          const SizedBox(width: 28),
                          Expanded(child: output),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [prompt, const SizedBox(height: 20), output],
                      ),
              ),
            ),
            if (widget.examples.length > 1) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.examples.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _ExampleChip(
                    key: ValueKey('store-example:$i'),
                    entry: widget.entry,
                    example: widget.examples[i],
                    selected: i == _index,
                    progress: _dwellClock,
                    onTap: i == _index ? null : () => _select(i),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    // Const where it is used, so it must ask for the theme itself to follow a flip.
    grid.AppTheme.watch(context);
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: grid.AppPalette.accentOnSurface,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: grid.AppPalette.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PromptPane extends StatelessWidget {
  const _PromptPane({
    required this.entry,
    required this.example,
    required this.typing,
    required this.large,
    required this.onTry,
  });

  final DshEntry entry;
  final StoreExample example;
  final Animation<double> typing;
  final bool large;
  final ValueChanged<String>? onTry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Eyebrow('YOU ASK'),
      const SizedBox(height: 14),
      AnimatedBuilder(
        animation: typing,
        builder: (context, _) {
          final prompt = example.prompt;
          final shown = (prompt.length * typing.value).round().clamp(
            0,
            prompt.length,
          );
          final typingNow = shown < prompt.length;
          return Semantics(
            label: prompt,
            excludeSemantics: true,
            child: Text.rich(
              key: const ValueKey('store-showcase-prompt'),
              TextSpan(
                children: [
                  TextSpan(text: '“${prompt.substring(0, shown)}'),
                  // The rest is laid out but unseen, so the pane does not grow as it types.
                  TextSpan(
                    text: '${prompt.substring(shown)}”',
                    style: TextStyle(
                      color: typingNow
                          ? Colors.transparent
                          : grid.AppPalette.textPrimary,
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: large ? 24 : 20,
                height: 1.32,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: grid.AppPalette.textPrimary,
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          EngineMark(engine: entry.id, displayName: entry.name, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${entry.name} harness',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: grid.AppPalette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            LucideIcons.arrowRight300,
            size: 14,
            color: grid.AppPalette.textFaint,
          ),
        ],
      ),
      const SizedBox(height: 22),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            key: const ValueKey('store-try-prompt'),
            onPressed: onTry == null ? null : () => onTry!(example.prompt),
            icon: const Icon(LucideIcons.sparkles300, size: 16),
            label: const Text('Try this prompt'),
            style: FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: const StadiumBorder(),
            ),
          ),
          AppIconButton(
            key: const ValueKey('store-copy-prompt'),
            icon: LucideIcons.copy300,
            tooltip: 'Copy prompt',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: example.prompt));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Prompt copied')));
              }
            },
          ),
        ],
      ),
    ],
  );
}

class _OutputPane extends StatelessWidget {
  const _OutputPane({
    required this.entry,
    required this.example,
    required this.typing,
    required this.reveal,
  });

  final DshEntry entry;
  final StoreExample example;
  final Animation<double> typing;
  final Animation<double> reveal;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _Eyebrow('IT MAKES', trailing: example.caption),
      const SizedBox(height: 14),
      AspectRatio(
        aspectRatio: 16 / 10,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF111316)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: reveal,
                  builder: (context, child) => Opacity(
                    opacity: Curves.easeOut.transform(reveal.value),
                    child: Transform.scale(
                      scale:
                          1.04 -
                          0.04 * Curves.easeOutCubic.transform(reveal.value),
                      child: child,
                    ),
                  ),
                  child: _OutputPicture(entry: entry, example: example),
                ),
                // The harness at work: a light sweeping across while the prompt is still arriving.
                AnimatedBuilder(
                  animation: Listenable.merge([typing, reveal]),
                  builder: (context, _) {
                    final working = typing.value > 0 && reveal.value == 0;
                    if (!working) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment(-1.2 + 2.4 * typing.value, 0),
                      child: FractionallySizedBox(
                        widthFactor: 0.35,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                grid.AppPalette.accent.withValues(alpha: 0.18),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _OutputPicture extends StatelessWidget {
  const _OutputPicture({required this.entry, required this.example});
  final DshEntry entry;
  final StoreExample example;

  @override
  Widget build(BuildContext context) {
    final image = example.image;
    final placeholder = _OutputPlaceholder(entry: entry);
    if (image == null) return placeholder;
    return Image.network(
      image,
      key: ValueKey('store-showcase-image:$image'),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: example.caption ?? 'What ${entry.name} made',
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class _OutputPlaceholder extends StatelessWidget {
  const _OutputPlaceholder({required this.entry});
  final DshEntry entry;

  @override
  Widget build(BuildContext context) => Center(
    child: Opacity(
      opacity: 0.55,
      child: EngineMark(engine: entry.id, displayName: entry.name, size: 64),
    ),
  );
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({
    super.key,
    required this.entry,
    required this.example,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final DshEntry entry;
  final StoreExample example;
  final bool selected;
  final Animation<double> progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: example.prompt,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? grid.AppSurface.selectedFill
              : grid.AppPalette.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? grid.AppPalette.accent.withValues(alpha: 0.6)
                : grid.AppPalette.divider,
          ),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 54,
                    child: ColoredBox(
                      color: const Color(0xFF111316),
                      child: example.image == null
                          ? Center(
                              child: EngineMark(
                                engine: entry.id,
                                displayName: entry.name,
                                size: 22,
                              ),
                            )
                          : Image.network(
                              example.image!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Center(
                                child: EngineMark(
                                  engine: entry.id,
                                  displayName: entry.name,
                                  size: 22,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    example.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: selected
                          ? grid.AppPalette.textPrimary
                          : grid.AppPalette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (selected)
              Positioned(
                left: 0,
                right: 0,
                bottom: -8,
                child: AnimatedBuilder(
                  animation: progress,
                  builder: (context, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.value,
                    child: Container(height: 2, color: grid.AppPalette.accent),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
