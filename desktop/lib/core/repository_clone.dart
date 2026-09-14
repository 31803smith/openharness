import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class GitHubRepository {
  const GitHubRepository._(this.url, this.name);
  final String url, name;

  static GitHubRepository? parse(String input) {
    final text = input.trim();
    final ssh = text.startsWith('git@github.com:');
    String path;
    if (ssh) {
      path = text.substring('git@github.com:'.length);
    } else {
      final uri = Uri.tryParse(
        text.contains('://') ? text : 'https://github.com/$text',
      );
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasQuery ||
          uri.hasFragment) {
        return null;
      }
      path = uri.path.replaceFirst(RegExp(r'^/'), '');
    }
    path = path
        .replaceFirst(RegExp(r'/$'), '')
        .replaceFirst(RegExp(r'\.git$'), '');
    final parts = path.split('/');
    if (parts.length != 2 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,38}$').hasMatch(parts[0]) ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(parts[1]) ||
        parts[1] == '.' ||
        parts[1] == '..') {
      return null;
    }
    return GitHubRepository._(
      ssh ? 'git@github.com:$path.git' : 'https://github.com/$path.git',
      parts[1],
    );
  }
}

class RepositoryCloneException implements Exception {
  const RepositoryCloneException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef GitCloneProcess = Future<Process> Function(
  List<String> arguments,
  Map<String, String> environment,
);

/// Clones into a private staging directory. Existing working folders are never
/// reused or removed, and a failed/cancelled clone leaves no partial project.
class RepositoryClone {
  RepositoryClone({GitCloneProcess? startProcess})
    : _startProcess = startProcess ?? _startGit;
  final GitCloneProcess _startProcess;
  Process? _process;
  bool _cancelled = false;
  bool _started = false;

  static Future<Process> _startGit(
    List<String> arguments,
    Map<String, String> environment,
  ) => Process.start('git', arguments, environment: environment);

  void cancel() {
    _cancelled = true;
    _process?.kill();
  }

  Future<String> run(GitHubRepository repository, String parent) async {
    if (_started) throw StateError('A clone can only be started once.');
    _started = true;
    Directory? staging;
    Timer? deadline;
    var timedOut = false;
    try {
      if (!p.isAbsolute(parent) || !await Directory(parent).exists()) {
        throw const RepositoryCloneException(
          'Choose an existing destination folder.',
        );
      }
      final destination = p.join(parent, repository.name);
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw RepositoryCloneException(
          '“${repository.name}” already exists here. Choose another destination, or open that folder.',
        );
      }
      if (_cancelled) throw const RepositoryCloneException('Clone cancelled.');
      staging = await Directory(parent).createTemp('.harness-clone-');
      final checkout = p.join(staging.path, 'checkout');
      final process = _process = await _startProcess(
        ['clone', '--', repository.url, checkout],
        {
          'GIT_TERMINAL_PROMPT': '0',
          'GCM_INTERACTIVE': 'Never',
          if (!Platform.environment.containsKey('GIT_SSH_COMMAND'))
            'GIT_SSH_COMMAND': 'ssh -oBatchMode=yes -oConnectTimeout=20',
        },
      );
      unawaited(process.stdin.close());
      if (_cancelled) process.kill();
      deadline = Timer(const Duration(minutes: 5), () {
        timedOut = true;
        process.kill();
      });
      // Drain both streams, retaining only a bounded diagnostic for classifying
      // failures. Git URLs/credential-helper output never enter the UI or logs.
      final output = process.stdout.drain<void>();
      var diagnostic = '';
      final errors = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach((chunk) {
            if (diagnostic.length < 8192) {
              diagnostic += chunk.substring(
                0,
                chunk.length.clamp(0, 8192 - diagnostic.length),
              );
            }
          });
      final code = await process.exitCode;
      await output;
      await errors;
      if (_cancelled) throw const RepositoryCloneException('Clone cancelled.');
      if (timedOut) {
        throw const RepositoryCloneException(
          'Cloning took too long. Check the connection and retry.',
        );
      }
      if (code != 0) {
        if (RegExp(
          r'authentication|permission denied|could not read Username|repository not found',
          caseSensitive: false,
        ).hasMatch(diagnostic)) {
          throw const RepositoryCloneException(
            'Could not access this repository. Check the URL and your GitHub access on this computer.',
          );
        }
        throw const RepositoryCloneException(
          'Could not clone the repository. Check the URL and connection, then retry.',
        );
      }
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw RepositoryCloneException(
          '“${repository.name}” was created while cloning. Choose another destination.',
        );
      }
      await Directory(checkout).rename(destination);
      return destination;
    } on ProcessException {
      throw const RepositoryCloneException(
        'Git could not start. Install Git on this computer, then retry.',
      );
    } on FileSystemException {
      throw const RepositoryCloneException(
        'Could not write to this destination. Choose a folder you can edit.',
      );
    } finally {
      deadline?.cancel();
      _process = null;
      if (staging != null) {
        try {
          if (await staging.exists()) await staging.delete(recursive: true);
        } on FileSystemException {
          /* The checkout outcome remains authoritative. */
        }
      }
    }
  }
}
