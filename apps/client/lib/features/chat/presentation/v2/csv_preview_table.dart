import 'package:flutter/material.dart';

/// CSV 内嵌预览表，办公结果区用。
class CsvPreviewTable extends StatelessWidget {
  const CsvPreviewTable({super.key, required this.rows});
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cols = rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
        children: [
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: i == 0
                  ? BoxDecoration(color: theme.colorScheme.surfaceContainerLow)
                  : null,
              children: [
                for (var c = 0; c < cols; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      c < rows[i].length ? rows[i][c] : '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
