import 'package:flutter/material.dart';

import '../../theme/design_system.dart';

class CvDraftPreviewPanel extends StatelessWidget {
  const CvDraftPreviewPanel({
    required this.sections,
    required this.sectionValues,
    required this.technicalDetailsTitle,
    required this.technicalDetailsHint,
    required this.rawDraftLabel,
    this.activeSectionId,
    this.rawDraft,
    super.key,
  });

  final Map<String, String> sections;
  final Map<String, String> sectionValues;
  final String technicalDetailsTitle;
  final String technicalDetailsHint;
  final String rawDraftLabel;
  final String? activeSectionId;
  final String? rawDraft;

  @override
  Widget build(BuildContext context) {
    final entries = sections.entries.toList(growable: false);
    final hasRawDraft = rawDraft != null && rawDraft!.trim().isNotEmpty;
    final activeLabel = activeSectionId == null ? null : sections[activeSectionId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F7F3),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.softSurfaceBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CV',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: AppColors.secondaryText,
                                letterSpacing: 1.4,
                              ),
                        ),
                        Text(
                          activeLabel != null && activeLabel.trim().isNotEmpty
                              ? activeLabel
                              : technicalDetailsTitle,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final entry in entries) ...[
                _RenderedSectionCard(
                  title: entry.value,
                  value: sectionValues[entry.key] ?? '',
                  isActive: activeSectionId == entry.key,
                ),
                if (entry != entries.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          technicalDetailsTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (!hasRawDraft)
          Text(
            technicalDetailsHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.secondaryText,
                ),
          )
        else
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            title: Text(rawDraftLabel),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  technicalDetailsHint,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.softSurfaceBorder),
                ),
                child: SelectableText(
                  rawDraft!.trim().length > 2000
                      ? '${rawDraft!.trim().substring(0, 2000)}\n\n...'
                      : rawDraft!.trim(),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _RenderedSectionCard extends StatelessWidget {
  const _RenderedSectionCard({
    required this.title,
    required this.value,
    required this.isActive,
  });

  final String title;
  final String value;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? '—' : value.trim();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.softSurfaceBorder,
          width: isActive ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary : AppColors.secondaryText,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isActive ? AppColors.primary : AppColors.navy,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayValue,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.35,
                  color: AppColors.secondaryText,
                ),
          ),
        ],
      ),
    );
  }
}