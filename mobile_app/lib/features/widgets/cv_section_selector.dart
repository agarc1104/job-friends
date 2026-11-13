import 'package:flutter/material.dart';

class CvSectionSelector extends StatelessWidget {
  const CvSectionSelector({
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
    super.key,
  });

  final Map<String, String> sections;
  final String selectedSection;
  final ValueChanged<String> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sections.entries.map((entry) {
        final isSelected = selectedSection == entry.key;
        return ChoiceChip(
          label: Text(entry.value),
          selected: isSelected,
          onSelected: (_) => onSectionSelected(entry.key),
        );
      }).toList(),
    );
  }
}