import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/repository_clone.dart';
import 'package:harness/widgets/clone_repository_dialog.dart';

class _Folders extends FileSelectorPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => '/work';
}

class _Clone extends RepositoryClone {
  final pending = Completer<String>();
  bool cancelled = false;
  @override
  Future<String> run(GitHubRepository repository, String parent) =>
      pending.future;
  @override
  void cancel() {
    cancelled = true;
  }
}

void main() {
  testWidgets(
    'clone failure preserves inputs; retry returns the new working folder',
    (tester) async {
      final original = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _Folders();
      addTearDown(() => FileSelectorPlatform.instance = original);
      var clone = _Clone();
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) =>
                      CloneRepositoryDialog(createClone: () => clone),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Clone repository');
      final input = find.byKey(const ValueKey('clone-repository-url'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(input, 'owner/project');
      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();
      expect(tester.widget<TextField>(input).readOnly, isTrue);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      clone.pending.completeError(
        const RepositoryCloneException('Please check your GitHub access.'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'owner/project');
      expect(find.text('/work'), findsOneWidget);
      expect(find.text('Please check your GitHub access.'), findsOneWidget);
      clone = _Clone();
      await tester.tap(submit);
      await tester.pump();
      clone.pending.complete('/work/project');
      await tester.pumpAndSettle();
      expect(result, '/work/project');
      expect(input, findsNothing);
    },
  );
}
