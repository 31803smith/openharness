// The marks a harness's verdict puts in a pane header: the chip (ready, or how
// far from it) and the phase strip (where the work is). One file, so the
// terminal pane and the viewer pane draw them the same.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/models.dart';
import '../theme/app_theme.dart';

class VerdictChip extends StatelessWidget {
  const VerdictChip({super.key, required this.verdict});

  final AgentVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = verdict.ready
        ? ('Ready', AppColors.success, LucideIcons.circleCheck)
        : verdict.errors > 0
        ? (
            '${verdict.errors} ${verdict.errors == 1 ? 'error' : 'errors'}',
            AppColors.danger,
            LucideIcons.circleX,
          )
        : verdict.warnings > 0
        ? (
            '${verdict.warnings} ${verdict.warnings == 1 ? 'warning' : 'warnings'}',
            AppColors.warning,
            LucideIcons.triangleAlert,
          )
        : ('Checked', AppColors.mutedStrong, LucideIcons.circleDashed);
    return Tooltip(
      message: verdict.summary ?? label,
      child: Semantics(
        label: 'Verdict: $label',
        child: Container(
          key: const ValueKey('pane-verdict-chip'),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: .35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontFamily: AppFonts.sans,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the work is: every phase the verdict names, in order, with the one
/// under way emphasised. Read-only — the harness moves it, not the user.
class PhaseStrip extends StatelessWidget {
  const PhaseStrip({super.key, required this.phases});

  final List<AgentPhase> phases;

  @override
  Widget build(BuildContext context) {
    final active = phases.indexWhere((p) => p.state == AgentPhaseState.active);
    final label = active < 0
        ? phases.map((p) => p.name).join(', ')
        : '${phases[active].name}, ${active + 1} of ${phases.length}';
    return Semantics(
      label: 'Phase: $label',
      child: Row(
        key: const ValueKey('pane-phase-strip'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < phases.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  '·',
                  style: TextStyle(color: AppColors.textSoft, fontSize: 11),
                ),
              ),
            _PhaseMark(phase: phases[i]),
          ],
        ],
      ),
    );
  }
}

class _PhaseMark extends StatelessWidget {
  const _PhaseMark({required this.phase});

  final AgentPhase phase;

  @override
  Widget build(BuildContext context) {
    final (icon, color, weight) = switch (phase.state) {
      AgentPhaseState.done => (
        LucideIcons.check,
        AppColors.success,
        FontWeight.w500,
      ),
      AgentPhaseState.active => (
        LucideIcons.circleDot,
        AppColors.text,
        FontWeight.w700,
      ),
      AgentPhaseState.failed => (
        LucideIcons.x,
        AppColors.danger,
        FontWeight.w500,
      ),
      AgentPhaseState.pending => (null, AppColors.textSoft, FontWeight.w500),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          phase.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: weight, color: color),
        ),
      ],
    );
  }
}
