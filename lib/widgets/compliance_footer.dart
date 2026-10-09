import 'package:flutter/material.dart';

import '../theme/severity_style.dart';

/// Mandatory compliance footer for any screen that shows a clinical result.
///
/// Build pack requirement (`.github/copilot-instructions.md` §5):
/// every result screen shows
///  * the CPIC reference,
///  * the rule-set version,
///  * the "Decision support only …" disclaimer, and
///  * the date of the rule snapshot.
class ComplianceFooter extends StatelessWidget {
  /// CPIC guideline citation, e.g. "CPIC Guideline for CYP2D6 and Codeine".
  final String? cpicReference;

  /// Version of the rule pack that produced the result.
  final String? ruleSetVersion;

  /// ISO date of the rule snapshot, e.g. "2026-09-04".
  final String? snapshotDate;

  /// Whether the explanation beside this footer came from the on-device LLM
  /// (AI-simplified) or from the deterministic template fallback.
  final bool aiSimplified;

  const ComplianceFooter({
    super.key,
    this.cpicReference,
    this.ruleSetVersion,
    this.snapshotDate,
    this.aiSimplified = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guideline = (cpicReference == null || cpicReference!.trim().isEmpty)
        ? 'CPIC guideline reference not available for this record.'
        : cpicReference!.trim();
    final version = (ruleSetVersion == null || ruleSetVersion!.trim().isEmpty)
        ? 'bundled'
        : ruleSetVersion!.trim();
    final snapshot = (snapshotDate == null || snapshotDate!.trim().isEmpty)
        ? 'not recorded'
        : snapshotDate!.trim();
    final explanationSource = aiSimplified
        ? 'AI-simplified explanation'
        : 'Template explanation';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.gavel_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AdvisoryCopy.decisionSupportOnly,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MetaRow(
            icon: Icons.menu_book_outlined,
            label: 'Guideline',
            value: guideline,
          ),
          _MetaRow(
            icon: Icons.verified_outlined,
            label: 'Rule snapshot',
            value: 'v$version',
          ),
          _MetaRow(
            icon: Icons.event_outlined,
            label: 'Snapshot date',
            value: snapshot,
          ),
          _MetaRow(
            icon: Icons.auto_awesome_outlined,
            label: 'Explanation',
            value: explanationSource,
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
