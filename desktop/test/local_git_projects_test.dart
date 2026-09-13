import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_git_projects.dart';

void main() {
  test('local Git metadata shares repository identity and watches worktree branches', () async {
    final fixture = await Directory.systemTemp.createTemp(
      'harness-git-context-',
    );
    final root = fixture.path;
    final main = Directory('$root/repo/.git');
    await main.create(recursive: true);
    await File(
      '${main.path}/config',
    ).writeAsString('[remote "origin"]\n url = git@github.com:Team/Repo.git\n');
    await File('${main.path}/HEAD').writeAsString('ref: refs/heads/main\n');
    await Directory('$root/repo/src').create();
    final tree = Directory('$root/feature');
    await tree.create();
    final meta = Directory('${main.path}/worktrees/feature');
    await meta.create(recursive: true);
    await File('${tree.path}/.git').writeAsString('gitdir: ${meta.path}\n');
    await File('${meta.path}/commondir').writeAsString('../..\n');
    await File('${meta.path}/HEAD')
        .writeAsString('ref: refs/heads/feature/login\n');
    final changed = Completer<void>();
    late LocalGitProjects reader;
    reader = LocalGitProjects(
      onChanged: () {
        if (reader.cached(tree.path)?.branch == 'feature/fix' &&
            !changed.isCompleted) {
          changed.complete();
        }
      },
    );
    addTearDown(() async {
      reader.dispose();
      await fixture.delete(recursive: true);
    });
    await Future.wait([reader.read('$root/repo/src'), reader.read(tree.path)]);
    final project = reader.cached('$root/repo/src')!;
    expect(project.root, '$root/repo');
    expect(project.branch, 'main');
    expect(project.remote, 'github.com/team/repo');
    expect(reader.cached(tree.path)!.remote, project.remote);
    expect(reader.cached(tree.path)!.branch, 'feature/login');
    await reader.read(tree.path);
    expect(reader.cached('$root/repo/src'), same(project));
    await File('${meta.path}/HEAD')
        .writeAsString('ref: refs/heads/feature/fix\n');
    await changed.future.timeout(const Duration(seconds: 4));
    expect(reader.cached(tree.path)!.branch, 'feature/fix');
    expect(reader.cached('$root/repo/src'), same(project));
  });

  test(
    'remote identity removes credentials and respects host and port semantics',
    () {
      expect(
        canonicalGitRemote('https://user:secret@GitHub.com/TEAM/Repo.git'),
        'github.com/team/repo',
      );
      expect(
        canonicalGitRemote('ssh://git@example.org:2222/Team/Repo.git'),
        'example.org:2222/Team/Repo',
      );
      expect(
        canonicalGitRemote('git@example.org:Team/Repo.git'),
        'example.org/Team/Repo',
      );
      expect(canonicalGitRemote('file:///private/repo'), isNull);
    },
  );
}
