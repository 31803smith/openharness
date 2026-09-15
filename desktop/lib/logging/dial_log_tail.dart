import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_log.dart';
import 'log_file.dart';
import 'log_stream.dart';

/// Base name of the dial's per-day file under `~/.harness/logs`, written by the
/// CLI daemon (`cli/src/cable/dialLog.ts`), never by this app.
const String kDialLogBase = 'dial';

/// Follows `dial-YYYYMMDD.log` into the in-memory [LogStream], so the dial is
/// a source in Settings ▸ Debug beside the app's own.
///
/// The other sources are *mirrors* — the app writes the file and the ring at
/// once. This one cannot be: the daemon writes the dial's file, and the app
/// only reads it. So it tails: every second it reads whatever bytes were
/// appended since last time, one entry per line, category `dial`. On first
/// start it takes only the last [_catchUpBytes] of today's file, enough for
/// the recent context without replaying a whole day into a 500-entry ring.
///
/// Levels come from the line itself: the firmware's `W (ticks)` / `E (ticks)`
/// prefixes, and a `[daemon]` line is the daemon speaking. The file is the
/// truth; a parse that fails still shows the raw line.
class DialLogTail {
  DialLogTail(
    this.directory,
    this.stream, {
    DateTime Function()? clock,
    this.interval = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now;

  final Directory directory;
  final LogStream stream;
  final Duration interval;
  final DateTime Function() _clock;

  static const int _catchUpBytes = 16 * 1024;

  Timer? _timer;
  String? _day;
  int _offset = 0;
  String _partial = '';
  // Set when the catch-up window opened mid-line: the first "line" read is a
  // fragment and is dropped rather than shown as a half sentence.
  bool _dropFirst = false;

  File get currentFile =>
      File('${directory.path}/${dailyLogName(kDialLogBase, _clock())}');

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(poll()));
    unawaited(poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One read of whatever is new. Public so a test can drive it without a
  /// timer; safe to call when nothing changed.
  Future<void> poll() async {
    try {
      final now = _clock();
      final day = dailyLogName(kDialLogBase, now);
      final file = currentFile;
      if (day != _day) {
        // A new day (or the first poll): start from the tail, not the top.
        _day = day;
        _partial = '';
        _offset = 0;
        _dropFirst = false;
        if (await file.exists()) {
          final length = await file.length();
          if (length > _catchUpBytes) {
            _offset = length - _catchUpBytes;
            _dropFirst = true;
          }
        }
      }
      if (!await file.exists()) return;
      final length = await file.length();
      if (length < _offset) _offset = 0; // truncated or replaced — start over
      if (length == _offset) return;
      final handle = await file.open();
      try {
        await handle.setPosition(_offset);
        final bytes = await handle.read(length - _offset);
        _offset = length;
        _ingest(const Utf8Decoder(allowMalformed: true).convert(bytes));
      } finally {
        await handle.close();
      }
    } on Object {
      // A log reader must never become a source of log noise about itself.
    }
  }

  void _ingest(String chunk) {
    final text = _partial + chunk;
    final lines = text.split('\n');
    _partial = lines
        .removeLast(); // '' after a trailing newline, else a fragment
    for (final line in lines) {
      if (_dropFirst) {
        _dropFirst = false;
        continue;
      }
      if (line.isEmpty) continue;
      final parsed = parseDialLine(line);
      stream.add(parsed.level, 'dial', parsed.message);
    }
  }
}

/// One dial log line, minus its wall-clock stamp, with a level read off it.
typedef ParsedDialLine = ({AppLogLevel level, String message});

/// `2026-09-15T03:53:52.001Z W (27793) touch: …` → warn, `W (27793) touch: …`.
/// `2026-09-15T03:56:22.418Z [daemon] following …` → info, `[daemon] following …`.
ParsedDialLine parseDialLine(String line) {
  final space = line.indexOf(' ');
  final message = space > 0 && line[space - 1] == 'Z'
      ? line.substring(space + 1)
      : line;
  final level = message.startsWith('E (')
      ? AppLogLevel.error
      : message.startsWith('W (')
      ? AppLogLevel.warn
      : message.startsWith('D (') || message.startsWith('V (')
      ? AppLogLevel.debug
      : AppLogLevel.info;
  return (level: level, message: message);
}
