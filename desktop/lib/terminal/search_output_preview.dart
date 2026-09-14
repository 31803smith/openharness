import 'dart:math' as math;

import 'package:xterm/xterm.dart';

/// A small, inert excerpt of output the app already holds. Reading a preview
/// never changes the terminal, its viewport, selection, input or connection.
class SearchOutputPreview {
  const SearchOutputPreview(this.text);

  // Covers the maximum 120-row viewport plus a small amount of scrollback,
  // including a short prompt near the top of an otherwise empty tall pane.
  static const scannedLines = 160;
  static const shownColumns = 192;
  static const shownCharacters = 720;
  final String text;
  static final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');
  static final _rules = RegExp(r'[-─━═_╌┄]{4,}');
  static final _frame = RegExp(r'^[│┃┆╎┊┇]+\s*|\s*[│┃┆╎┊┇]+$');
  static final _prompt = RegExp(r'^[>›❯_$▌█\s]+$');
  static final _blockStart = RegExp(r'^(?:[>›❯•●◦]|[-*]\s|\d+\.\s)');
  static final _recap = RegExp(r'^(?:[—–-]\s*)?Conversation recap$');
  static final _worked = RegExp(r'^[—–-]\s*Worked for \d');
  static final _inputHint = RegExp(r'^Ask (Codex|Claude) to ');
  static final _indented = RegExp(r'^\s');

  static SearchOutputPreview capture(Terminal? terminal) {
    if (terminal == null) return const SearchOutputPreview('');
    final lines = terminal.buffer.lines;
    final logical = <String>[];
    final start = math.max(0, lines.length - scannedLines);
    for (var row = start; row < lines.length; row++) {
      // getText works in terminal cells, so a wide Unicode character is not
      // split as it could be by slicing an arbitrary UTF-16 string.
      final text = lines[row]
          .getText(0, shownColumns)
          .replaceAll(_controls, '')
          .trimRight();
      if (lines[row].isWrapped && logical.isNotEmpty) {
        logical[logical.length - 1] += text;
      } else {
        logical.add(text);
      }
    }
    final blocks = <String>[];
    var paragraph = '';
    void finish() {
      if (paragraph.isNotEmpty) blocks.add(paragraph);
      paragraph = '';
    }

    for (final line in logical) {
      final text = line.replaceAll(_rules, '').trim().replaceAll(_frame, '');
      if (text.isEmpty ||
          _prompt.hasMatch(text) ||
          _recap.hasMatch(text) ||
          _worked.hasMatch(text) ||
          _inputHint.hasMatch(text)) {
        finish();
        continue;
      }
      if (_blockStart.hasMatch(text) || !_indented.hasMatch(line)) {
        finish();
      }
      paragraph = paragraph.isEmpty ? text : '$paragraph $text';
    }
    finish();
    // Show complete recent paragraphs, not the bottom of a wrapped terminal
    // viewport. This is a reading excerpt, never a second terminal renderer.
    final recentBlocks = blocks.skip(math.max(0, blocks.length - 3)).toList();
    while (recentBlocks.length > 1 &&
        recentBlocks.join('\n\n').runes.length > shownCharacters) {
      recentBlocks.removeAt(0);
    }
    final recent = recentBlocks.join('\n\n');
    final characters = recent.runes.toList();
    return SearchOutputPreview(
      characters.length <= shownCharacters
          ? recent
          : '${String.fromCharCodes(characters.take(shownCharacters)).trimRight()}…',
    );
  }
}
