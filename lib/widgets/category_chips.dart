import 'package:flutter/material.dart';

/// Horizontal scrolling category filter: "All" + one chip per category with its item count.
class CategoryChips extends StatelessWidget {
  final Map<String, int> counts; // category -> number of items
  final int total;
  final String? selected; // null = All
  final ValueChanged<String?> onSelected;

  const CategoryChips({
    super.key,
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelected,
  });

  Widget _chip(String label, int n, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label ($n)'),
        selected: isSelected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip('All', total, selected == null, () => onSelected(null)),
          for (final e in counts.entries)
            _chip(e.key, e.value, selected == e.key,
                () => onSelected(selected == e.key ? null : e.key)),
        ],
      ),
    );
  }
}