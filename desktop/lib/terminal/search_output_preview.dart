import 'dart:math' as math;

import 'package:xterm/xterm.dart';

/// A small, inert excerpt of output the app already holds. Reading a preview
/// never changes the terminal, its viewport, selection, input or connection.
class SearchOutputPreview {
  const SearchOutputPreview(this.text);

  // Covers the maximum 120-row viewport plus a small amount of scrollback,
  // including a short prompt near the top of an otherwise empty tall pane.
  static const scannedLines = 160;
  static const shownLines = 12;
  static const shownColumns = 192;
  final String text;
  static final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');

  static SearchOutputPreview capture(Terminal? terminal) {
    if (terminal == null) return const SearchOutputPreview('');
    final lines = terminal.buffer.lines;
    final excerpt = <String>[];
    final start = math.max(0, lines.length - scannedLines);
    for (var row = lines.length - 1; row >= start; row--) {
      // getText works in terminal cells, so a wide Unicode character is not
      // split as it could be by slicing an arbitrary UTF-16 string.
      final text = lines[row]
          .getText(0, shownColumns)
          .replaceAll(_controls, '')
          .trimRight();
      if (text.trim().isEmpty) continue;
      excerpt.add(text);
      if (excerpt.length == shownLines) break;
    }
    return SearchOutputPreview(excerpt.reversed.join('\n'));
  }
}
