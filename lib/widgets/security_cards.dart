import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class OnDevicePrivacyMicroCard extends StatelessWidget {
  final String? title;
  final String? subtext;

  const OnDevicePrivacyMicroCard({
    super.key,
    this.title,
    this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.mintSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.accentEmerald.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.accentEmerald.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: AppTheme.primaryEmerald,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title ?? 'On-Device Genomic Privacy',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.primaryDarkEmerald,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtext ??
                      'Raw genetic files are analyzed locally and never stored in the cloud. Encryption keys stay on your hardware.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.secondaryInk.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SecurityCalloutCard extends StatelessWidget {
  final String text;

  const SecurityCalloutCard({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.mintSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentEmerald.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.shield_outlined,
            color: AppTheme.primaryEmerald,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.secondaryInk,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
