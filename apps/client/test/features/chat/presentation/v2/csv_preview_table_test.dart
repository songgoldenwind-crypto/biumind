import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/task_artifacts.dart';
import 'package:biumind/features/chat/presentation/v2/csv_preview_table.dart';

void main() {
  testWidgets('csv preview renders header and cells', (tester) async {
    final rows = parseCsvPreview('name,count\n周报,3\n');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CsvPreviewTable(rows: rows)),
    ));
    expect(find.text('name'), findsOneWidget);
    expect(find.text('周报'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
