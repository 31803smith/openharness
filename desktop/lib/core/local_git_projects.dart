import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';

/// Compatibility for this computer's older daemon. Reads only Git metadata;
/// directory watches invalidate the cache when a checkout or remote changes.
/// No Git processes, network calls, terminal reads, or work on the render path.
class LocalGitProjects {
  LocalGitProjects({required this.onChanged});
  final void Function() onChanged;
  final _entries = <String, _LocalGitEntry>{};
  bool _disposed = false;

  AgentProject? cached(String cwd) => _entries[cwd]?.project;

  Future<void> read(String cwd) {
    if (_disposed || !p.isAbsolute(cwd)) return Future.value();
    final existing = _entries[cwd];
    if (existing != null) {
      if (existing.pending != null) return existing.pending!;
      if (existing.watchers.isNotEmpty ||
          DateTime.now().difference(existing.checkedAt) <
              const Duration(minutes: 1)) {
        return Future.value();
      }
      return existing.pending = _resolve(cwd, existing);
    }
    if (_entries.length >= 256) {
      _entries.remove(_entries.keys.first)?.dispose();
    }
    final entry = _LocalGitEntry();
    _entries[cwd] = entry;
    return entry.pending = _resolve(cwd, entry);
  }

  Future<void> _resolve(String cwd, _LocalGitEntry entry) async {
    try {
      var root = p.normalize(cwd);
      String? gitDir;
      for (var depth = 0; depth < 32; depth++) {
        final marker = p.join(root, '.git');
        final type = await FileSystemEntity.type(marker);
        if (type == FileSystemEntityType.directory) {
          gitDir = marker;
          break;
        }
        if (type == FileSystemEntityType.file) {
          final pointer = await _text(marker);
          if (pointer?.startsWith('gitdir: ') == true) {
            gitDir = p.normalize(p.join(root, pointer!.substring(8).trim()));
          }
          break;
        }
        final parent = p.dirname(root);
        if (parent == root) break;
        root = parent;
      }
      if (gitDir == null) {
        if (!_disposed && !entry.disposed && entry.project != null) {
          entry.project = null;
          onChanged();
        }
        return;
      }
      final shared = await _text(p.join(gitDir, 'commondir'));
      final common = shared == null
          ? gitDir
          : p.normalize(p.join(gitDir, shared.trim()));
      final head = (await _text(p.join(gitDir, 'HEAD')))?.trim();
      final config = await _text(p.join(common, 'config'));
      if (_disposed || entry.disposed) return;
      final branch = head?.startsWith('ref: refs/heads/') == true
          ? head!.substring(16)
          : head != null && RegExp(r'^[a-fA-F0-9]{40,64}$').hasMatch(head)
          ? 'Detached ${head.substring(0, 7)}'
          : null;
      final project = AgentProject.fromJson({
        'name': p.basename(root),
        'cwd': cwd,
        'root': root,
        'remote': _origin(config),
        'branch': branch,
      });
      if (entry.watchers.isEmpty) {
        for (final directory in {gitDir, common}) {
          try {
            entry.watchers.add(
              Directory(directory).watch().listen((event) {
                if (!{
                  'HEAD',
                  'config',
                  'commondir',
                }.contains(p.basename(event.path))) {
                  return;
                }
                entry.debounce?.cancel();
                entry.debounce = Timer(const Duration(milliseconds: 100), () {
                  if (!_disposed && !entry.disposed) {
                    entry.pending = _resolve(cwd, entry);
                  }
                });
              }, onError: (Object _) {}),
            );
          } on FileSystemException {
            // Metadata is still useful when the filesystem cannot watch it.
          }
        }
      }
      if (entry.project != project) {
        entry.project = project;
        onChanged();
      }
    } on FileSystemException {
      // A removed/unreadable working folder must not interfere with discovery.
    } finally {
      entry.checkedAt = DateTime.now();
      entry.pending = null;
    }
  }

  Future<String?> _text(String path) async {
    final file = File(path);
    try {
      if (await file.length() > 64 * 1024) return null;
      return await file.readAsString();
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  String? _origin(String? config) {
    if (config == null) return null;
    var origin = false;
    for (final line in config.split('\n')) {
      final text = line.trim();
      if (text.startsWith('[')) {
        origin = RegExp(
          r'^\[remote\s+"origin"\]$',
          caseSensitive: false,
        ).hasMatch(text);
      } else if (origin) {
        final match = RegExp(
          r'^url\s*=\s*(.+)$',
          caseSensitive: false,
        ).firstMatch(text);
        if (match != null) return canonicalGitRemote(match.group(1)!);
      }
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }
}

String? canonicalGitRemote(String raw) {
  raw = raw.trim();
  if (raw.startsWith('"') && raw.endsWith('"')) {
    raw = raw.substring(1, raw.length - 1);
  }
  final scp = RegExp(r'^(?:[^@/\s]+@)?([^:/\s]+):([^\s]+)$').firstMatch(raw);
  final uri = Uri.tryParse(
    scp != null && !raw.contains('://')
        ? 'ssh://${scp.group(1)}/${scp.group(2)}'
        : raw,
  );
  if (uri == null ||
      !{'ssh', 'https', 'http', 'git'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    return null;
  }
  var path = uri.path
      .replaceAll(RegExp(r'^/+|/+$'), '')
      .replaceFirst(RegExp(r'\.git$', caseSensitive: false), '');
  if (path.isEmpty || RegExp(r'[\x00-\x20]').hasMatch(path)) return null;
  final host = uri.host.toLowerCase();
  if (host == 'github.com' || host == 'bitbucket.org') {
    path = path.toLowerCase();
  }
  final defaultPort = switch (uri.scheme) {
    'ssh' => 22,
    'git' => 9418,
    'https' => 443,
    _ => 80,
  };
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '$host$port/$path';
}

class _LocalGitEntry {
  DateTime checkedAt = DateTime.now();
  AgentProject? project;
  Future<void>? pending;
  final watchers = <StreamSubscription<FileSystemEvent>>[];
  Timer? debounce;
  bool disposed = false;
  void dispose() {
    disposed = true;
    debounce?.cancel();
    for (final watcher in watchers) {
      unawaited(watcher.cancel());
    }
  }
}
