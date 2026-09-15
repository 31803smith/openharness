import 'dart:io';

import 'package:path/path.dart' as p;

import 'repository_clone.dart';

/// Folder preparation is explicit and runs only when New Agent is submitted.
/// Existing folders continue to use the ordinary agent_create cwd payload.
class ProjectFolderRequest {
  const ProjectFolderRequest.newProject() : repository = null;
  const ProjectFolderRequest.remote(GitHubRepository value)
    : repository = value;

  final GitHubRepository? repository;

  Map<String, String> get payload => {
    'projectSource': repository == null ? 'new' : 'remote',
    if (repository != null) 'repositoryUrl': repository!.url,
  };

  Future<String> prepareLocal({
    String? projectHome,
    RepositoryClone Function()? createClone,
  }) async {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (projectHome == null && (home == null || !p.isAbsolute(home))) {
      throw const RepositoryCloneException(
        'Could not find your home folder. Choose Local to select a folder.',
      );
    }
    final root = Directory(projectHome ?? p.join(home!, 'harnesses'));
    try {
      await root.create(recursive: true);
      if (repository case final repo?) {
        return await (createClone?.call() ?? RepositoryClone()).run(
          repo,
          root.path,
        );
      }
      var next = BigInt.one;
      await for (final entry in root.list(followLinks: false)) {
        final match = RegExp(r'^agent-([1-9]\d*)$')
            .firstMatch(p.basename(entry.path));
        if (match == null) continue;
        final number = BigInt.parse(match.group(1)!);
        if (number >= next) next = number + BigInt.one;
      }
      for (;;) {
        final folder = p.join(root.path, 'agent-$next');
        next += BigInt.one;
        // Directory.create accepts an existing directory. The platform mkdir
        // command reserves it exclusively, so concurrent creates never share
        // a workspace. Paths are arguments, never shell text.
        final result = await Process.run('mkdir', [folder]);
        if (result.exitCode == 0) return folder;
        if (await FileSystemEntity.type(folder, followLinks: false) ==
            FileSystemEntityType.notFound) {
          throw FileSystemException('Could not create folder', folder);
        }
      }
    } on FileSystemException {
      throw const RepositoryCloneException(
        'Could not create a project folder. Choose Local to select a folder you can edit.',
      );
    } on ProcessException {
      throw const RepositoryCloneException(
        'Could not create a project folder. Choose Local to select a folder you can edit.',
      );
    }
  }
}
