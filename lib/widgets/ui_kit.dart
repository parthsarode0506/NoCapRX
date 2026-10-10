import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small shared widget kit used across NoCapRX screens so cards, badges,
/// banners and empty states all look and behave the same.
///
/// Deliberately presentation-only: no business logic, no services.

/// A soft, rounded surface card with an optional tap target.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final Color? borderColor;
  final List<BoxShadow>? shadow;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.spaceMd),
    this.onTap,
    this.color,
    this.gradient,
    this.borderColor,
    this.shadow,
    this.radius = AppTheme.radiusMd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null
            ? (color ?? (isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight))
            : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? (isDark ? AppTheme.cardBorderDark : AppTheme.cardBorder),
        ),
        boxShadow: shadow ?? (isDark ? null : AppTheme.softShadow),
      ),
      child: child,
    );

    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: decorated,
      ),
    );
  }
}

/// Section title with an optional subtitle and trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceSm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Compact rounded status pill. Uses an icon + text, never colour alone.
class PillBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const PillBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small statistic tile: icon, value and label.
class StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final tile = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: isDark ? AppTheme.cardBorderDark : AppTheme.cardBorder,
        ),
        boxShadow: isDark ? null : AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: tile,
      ),
    );
  }
}

enum NoticeTone { info, success, warning, danger }

/// Inline banner for errors, warnings and privacy/info notices.
class NoticeBanner extends StatelessWidget {
  final NoticeTone tone;
  final String message;
  final String? title;
  final IconData? icon;
  final Widget? action;

  const NoticeBanner({
    super.key,
    required this.message,
    this.tone = NoticeTone.info,
    this.title,
    this.icon,
    this.action,
  });

  ({Color fg, Color bg}) get _palette {
    switch (tone) {
      case NoticeTone.success:
        return (fg: AppTheme.safeGreen, bg: AppTheme.safeGreenBg);
      case NoticeTone.warning:
        return (fg: AppTheme.warningAmber, bg: AppTheme.warningAmberBg);
      case NoticeTone.danger:
        return (fg: AppTheme.dangerRed, bg: AppTheme.dangerRedBg);
      case NoticeTone.info:
        return (fg: AppTheme.infoBlue, bg: AppTheme.infoBlueBg);
    }
  }

  IconData get _icon {
    if (icon != null) return icon!;
    switch (tone) {
      case NoticeTone.success:
        return Icons.check_circle_outline_rounded;
      case NoticeTone.warning:
        return Icons.warning_amber_rounded;
      case NoticeTone.danger:
        return Icons.error_outline_rounded;
      case NoticeTone.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _palette;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? p.fg.withValues(alpha: 0.16) : p.bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: p.fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: p.fg, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: p.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? theme.colorScheme.onSurface : p.fg,
                    height: 1.4,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Consistent empty state with an icon, copy and optional call to action.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.mintSurface,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.accentEmerald.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(icon, size: 34, color: AppTheme.primaryEmerald),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Simple definition row: bold label on the left, value on the right.
class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
