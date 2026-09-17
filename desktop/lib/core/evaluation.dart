/// How a harness judges what it makes — the four methods its verdict reports as it works and its
/// store page declares before anyone runs it (`store/spec/README.md`, `evaluation`). One set of
/// words for both, so the pane and the product page cannot describe the same check differently.
library;

import 'package:flutter/foundation.dart' show immutable;

enum EvaluationMethod {
  /// The domain's own verifier: a compiler, a design-rule check, a simulator.
  tool,

  /// The request's measurable claims — sizes, counts, keys — measured on the output.
  checks,

  /// A fresh-context model, or a person, grading the output against a written rubric.
  review,

  /// Nothing trustworthy verifies this domain: the person is the judge.
  none;

  static EvaluationMethod? parse(Object? raw) => switch (raw) {
    'tool' => tool,
    'checks' => checks,
    'review' => review,
    'none' => none,
    _ => null,
  };

  /// One phrase a person reads: "Verified by LilyPond 2.24.4", "Checked against the request".
  String phrase(String? by) => switch (this) {
    tool => by == null ? 'Verified by the tool' : 'Verified by $by',
    checks =>
      by == null ? 'Checked against the request' : 'Checked against $by',
    review => by == null ? 'Reviewed against a rubric' : 'Reviewed against $by',
    none => 'No automatic check: you are the judge',
  };
}

/// Text off the wire, cleaned: control characters become spaces, blank is null, long is cut.
String? evaluationText(Object? raw, int max) {
  if (raw is! String) return null;
  final clean = raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').trim();
  if (clean.isEmpty) return null;
  return clean.length <= max ? clean : clean.substring(0, max);
}

/// One entry of a verdict's `evaluation`: what judged this output, whether it passed (null while it
/// has not run, and always for [EvaluationMethod.none]), and whether `ready` depends on it.
@immutable
class AgentEvaluation {
  const AgentEvaluation({
    required this.method,
    this.by,
    this.passed,
    this.gate = false,
    this.detail,
  });

  final EvaluationMethod method;
  final String? by;
  final bool? passed;
  final bool gate;
  final String? detail;

  static AgentEvaluation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final method = EvaluationMethod.parse(raw['method']);
    if (method == null) return null;
    final passed = raw['passed'];
    return AgentEvaluation(
      method: method,
      by: evaluationText(raw['by'], 80),
      passed: method == EvaluationMethod.none || passed is! bool
          ? null
          : passed,
      gate: method != EvaluationMethod.none && raw['gate'] == true,
      detail: evaluationText(raw['detail'], 200),
    );
  }

  /// One line for the status tooltip: "✓ Verified by LilyPond 2.24.4",
  /// "✗ Checked against brief: 16 bars — 12 of 16 bars", "○ Reviewed against a rubric · advisory".
  String get line {
    final mark = switch (passed) {
      true => '✓',
      false => '✗',
      null => method == EvaluationMethod.none ? '–' : '○',
    };
    final notes = [
      if (passed == null && method != EvaluationMethod.none) 'not run yet',
      if (!gate && method != EvaluationMethod.none) 'advisory',
    ];
    return [
      '$mark ${method.phrase(by)}',
      if (detail != null) ' — $detail',
      if (notes.isNotEmpty) ' · ${notes.join(', ')}',
    ].join();
  }

  @override
  bool operator ==(Object other) =>
      other is AgentEvaluation &&
      other.method == method &&
      other.by == by &&
      other.passed == passed &&
      other.gate == gate &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(method, by, passed, gate, detail);
}

/// How a store package says it judges its output: a method and what does it.
@immutable
class StoreEvaluation {
  const StoreEvaluation({required this.method, this.by});

  final EvaluationMethod method;
  final String? by;

  String get phrase => method.phrase(by);

  static StoreEvaluation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final method = EvaluationMethod.parse(raw['method']);
    if (method == null) return null;
    return StoreEvaluation(method: method, by: evaluationText(raw['by'], 80));
  }

  @override
  bool operator ==(Object other) =>
      other is StoreEvaluation && other.method == method && other.by == by;

  @override
  int get hashCode => Object.hash(method, by);
}
