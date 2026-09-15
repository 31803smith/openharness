import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/logging/app_log.dart';
import 'package:harness/logging/dial_log_tail.dart';
import 'package:harness/logging/log_export.dart';
import 'package:harness/logging/log_file.dart';
import 'package:harness/logging/log_stream.dart';

void main() {
  test('parseDialLine strips the stamp and reads the level', () {
    final w = parseDialLine('2026-09-15T03:53:52.001Z W (27793) touch: dead');
    expect(w.level, AppLogLevel.warn);
    expect(w.message, 'W (27793) touch: dead');
    final d = parseDialLine('2026-09-15T03:56:22.418Z [daemon] open on /dev/x');
    expect(d.level, AppLogLevel.info);
    expect(d.message, '[daemon] open on /dev/x');
    expect(parseDialLine('no stamp E (1) x').level, AppLogLevel.info);
    expect(parseDialLine('E (1) x').level, AppLogLevel.error);
  });

  test('tails the day file into the stream, only what is new', () async {
    final dir = Directory.systemTemp.createTempSync('dial-tail-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final now = DateTime(2026, 9, 15, 10);
    final file = File('${dir.path}/${dailyLogName(kDialLogBase, now)}');
    file.writeAsStringSync('2026-09-15T03:00:00.000Z I (1) ui: face: agent\n');
    final stream = LogStream();
    final tail = DialLogTail(dir, stream, clock: () => now);
    await tail.poll();
    expect(stream.entries.map((e) => e.message), ['I (1) ui: face: agent']);
    // A partial line waits for its newline.
    file.writeAsStringSync(
      '2026-09-15T03:00:01.000Z W (2) touch: pre',
      mode: FileMode.append,
    );
    await tail.poll();
    expect(stream.entries.length, 1);
    file.writeAsStringSync(
      'ss (1,2)\n2026-09-15T03:00:02.000Z [daemon] agents → 3\n',
      mode: FileMode.append,
    );
    await tail.poll();
    expect(stream.entries.map((e) => e.message).toList(), [
      '[daemon] agents → 3',
      'W (2) touch: press (1,2)',
      'I (1) ui: face: agent',
    ]);
    expect(stream.entries.every((e) => e.category == 'dial'), isTrue);
    expect(stream.entries[1].level, AppLogLevel.warn);
    // Nothing new: nothing added.
    await tail.poll();
    expect(stream.entries.length, 3);
  });

  test(
    'a big file is joined at its tail, dropping the opening fragment',
    () async {
      final dir = Directory.systemTemp.createTempSync('dial-tail-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final now = DateTime(2026, 9, 15, 10);
      final file = File('${dir.path}/${dailyLogName(kDialLogBase, now)}');
      final sb = StringBuffer();
      for (var i = 0; i < 2000; i++) {
        sb.writeln(
          '2026-09-15T03:00:00.000Z I ($i) ui: line number $i padding padding',
        );
      }
      file.writeAsStringSync(sb.toString());
      final stream = LogStream();
      await DialLogTail(dir, stream, clock: () => now).poll();
      expect(stream.entries.length, lessThan(2000));
      expect(
        stream.entries.first.message,
        'I (1999) ui: line number 1999 padding padding',
      );
      // Every entry is a whole line — no fragment from the window's opening.
      for (final e in stream.entries) {
        expect(e.message, startsWith('I ('));
      }
    },
  );

  test('parseLogExport reads the CLI answer', () {
    final ok = parseLogExport(
      '{"path":"/x/harness-logs.zip","included":["a"],"bytes":1}',
    );
    expect(ok.path, '/x/harness-logs.zip');
    expect(ok.included, ['a']);
    expect(ok.error, isNull);
    expect(parseLogExport('nope').error, contains('unreadable'));
    expect(parseLogExport('{"bytes":1}').error, 'no path in answer');
  });
}
