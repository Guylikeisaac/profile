import 'package:flutter/material.dart';

import '../../../shared/widgets/app_button.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/theme_context_ext.dart';

/// Centered empty state for sections without data (Experience, Education, ...).
class SectionEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const SectionEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tokens = context.tokensOrDefault;
    // Full width so the column actually centres within the card, instead of
    // shrink-wrapping its content and hugging the left edge.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: tokens.textTertiary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: tokens.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Failure state for a profile section that loads on its own (Certifications,
/// References).
///
/// Deliberately keeps the section visible with a Retry rather than hiding it:
/// a section that vanishes on a 500 reads as "you have none", which is a
/// different and wrong statement.
class SectionErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const SectionErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokensOrDefault;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 24, color: tokens.textTertiary),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: tokens.textTertiary),
          ),
          const SizedBox(height: 4),
          AppButton.text(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}
