import 'package:flutter/material.dart';

import '../../l10n/localized_text.dart';
import '../../theme/design_system.dart';
import 'privacy_policy_content.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = privacyContentForLocale(Localizations.localeOf(context));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'legal.privacyTitle')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          Text(
            '${tr(context, 'legal.privacyUpdatedOn')} ${content.versionLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.secondaryText,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            content.intro,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final section in content.sections) ...[
            Text(
              section.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final paragraph in section.paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(paragraph),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
