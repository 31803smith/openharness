import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> browseNewAgentProject(WidgetTester tester) async {
  final browse = find.byKey(const Key('new-agent-project-browse'));
  await tester.ensureVisible(browse);
  await tester.tap(browse);
}
