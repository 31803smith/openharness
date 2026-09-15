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
    final root = Directory(projectHome ?? p.join(home!, 'Harness Projects'));
    try {
      await root.create(recursive: true);
      if (repository case final repo?) {
        return await (createClone?.call() ?? RepositoryClone()).run(
          repo,
          root.path,
        );
      }
      // The OS reserves a unique folder atomically. No name prompt or existing
      // project is needed, and two deliberate creations cannot share a folder.
      return (await root.createTemp('project-')).path;
    } on FileSystemException {
      throw const RepositoryCloneException(
        'Could not create a project folder. Choose Local to select a folder you can edit.',
      );
    }
  }
}
