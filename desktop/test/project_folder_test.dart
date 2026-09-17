import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/project_folder.dart';
import 'package:harness/core/repository_clone.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'new projects use unique folders and preserve existing projects',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'harness-new-project-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final existing = File(p.join(root.path, 'keep.txt'));
      await existing.writeAsString('keep');
      const request = ProjectFolderRequest.newProject();
      final folders = await Future.wait([
        request.prepareLocal(projectHome: root.path),
        request.prepareLocal(projectHome: root.path),
      ]);
      expect(folders.toSet(), hasLength(2));
      expect(folders.map(p.basename).toSet(), {'harness-1', 'harness-2'});
      expect(folders.every((folder) => p.isWithin(root.path, folder)), isTrue);
      expect(await existing.readAsString(), 'keep');
      expect(request.payload, {'projectSource': 'new'});
      await File(p.join(root.path, 'agent-4')).writeAsString('keep');
      expect(
        p.basename(await request.prepareLocal(projectHome: root.path)),
        'harness-5',
      );
      expect(await File(p.join(root.path, 'agent-4')).readAsString(), 'keep');
    },
  );
  test(
    'a new project is numbered past the names agents already answer to',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'harness-new-project-names-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      await Directory(p.join(root.path, 'harness-42')).create();
      const request = ProjectFolderRequest.newProject();
      // The agent in harness-41 answers to harness-42, the one in harness-42 to harness-43.
      final folder = await request.prepareLocal(
        projectHome: root.path,
        namesInUse: const ['harness-42', 'harness-43', 'Lamp', 'agent-7x'],
      );
      expect(p.basename(folder), 'harness-44');
      expect(
        p.basename(await request.prepareLocal(projectHome: root.path)),
        'harness-45',
      );
    },
  );
  test(
    'remote repository uses the existing safe clone on this computer',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'harness-remote-project-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = p.join(root.path, 'source.git');
      expect(
        (await Process.run('git', ['init', '--bare', source])).exitCode,
        0,
      );
      final request = ProjectFolderRequest.remote(
        GitHubRepository.parse('owner/repo')!,
      );
      final folder = await request.prepareLocal(
        projectHome: p.join(root.path, 'projects'),
        createClone: () => RepositoryClone(
          startProcess: (args, environment) {
            expect(args[2], 'https://github.com/owner/repo.git');
            return Process.start('git', [
              'clone',
              '--',
              source,
              args.last,
            ], environment: environment);
          },
        ),
      );
      expect(await Directory(p.join(folder, '.git')).exists(), isTrue);
      expect(request.payload, {
        'projectSource': 'remote',
        'repositoryUrl': 'https://github.com/owner/repo.git',
      });
    },
  );
}
