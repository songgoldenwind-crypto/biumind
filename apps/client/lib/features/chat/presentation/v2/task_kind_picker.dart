import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/task_kind.dart';

class TaskKindPicker extends StatelessWidget {
  const TaskKindPicker({
    super.key,
    required this.kind,
    required this.onChanged,
  });

  final String kind;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.taskKindLabel,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: kTaskKindGeneral,
              label: Text(l.taskKindGeneral),
            ),
            ButtonSegment(
              value: kTaskKindOffice,
              label: Text(l.taskKindOffice),
            ),
            ButtonSegment(
              value: kTaskKindCode,
              label: Text(l.taskKindCode),
            ),
          ],
          selected: {kind},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ],
    );
  }
}
