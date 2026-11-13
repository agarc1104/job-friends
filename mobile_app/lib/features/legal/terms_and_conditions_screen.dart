import 'package:flutter/material.dart';

import '../../l10n/localized_text.dart';
import '../../theme/design_system.dart';
import 'privacy_policy_screen.dart';
import 'terms_content.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  const TermsAndConditionsScreen({
    this.requireAcceptance = false,
    this.onAccepted,
    super.key,
  });

  final bool requireAcceptance;
  final Future<void> Function()? onAccepted;

  @override
  State<TermsAndConditionsScreen> createState() => _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  bool _acceptedCheckbox = false;
  bool _isSaving = false;

  Future<void> _accept() async {
    if (!widget.requireAcceptance || _isSaving || widget.onAccepted == null) {
      return;
    }

    if (!_acceptedCheckbox) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'legal.acceptRequiredError'))),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onAccepted!.call();
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = termsContentForLocale(Localizations.localeOf(context));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'legal.termsTitle')),
        automaticallyImplyLeading: !widget.requireAcceptance,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              children: [
                Text(
                  '${tr(context, 'legal.termsUpdatedOn')} ${content.versionLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  content.intro,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.privacy_tip_outlined),
                    label: Text(tr(context, 'legal.viewPrivacyPolicy')),
                  ),
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
          ),
          if (widget.requireAcceptance)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.softSurfaceBorder),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: CheckboxListTile(
                        value: _acceptedCheckbox,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  _acceptedCheckbox = value ?? false;
                                });
                              },
                        title: Text(tr(context, 'legal.acceptLabel')),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _accept,
                        child: Text(
                          _isSaving
                              ? tr(context, 'common.loading')
                              : tr(context, 'legal.acceptButton'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
