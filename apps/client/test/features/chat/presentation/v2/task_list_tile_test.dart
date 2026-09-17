import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/chat_models.dart';
import 'package:biumind/features/chat/domain/task_list_row.dart';
import 'package:biumind/features/chat/domain/task_status.dart';
import 'package:biumind/features/chat/presentation/v2/task_list_tile.dart';

void main() {
  testWidgets('awaiting write row shows status chip not a chat mode-dot',
      (tester) async {
    final model = buildTaskListRowModel(
      status: TaskStatus.awaiting,
      mode: ThreadMode.agent,
      attentionTool: 'Write',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListRowBody(
            title: '整理周报',
            model: model,
            statusLabel: '要写文件',
            executorLabel: '电脑',
            timeLabel: '刚刚',
          ),
        ),
      ),
    );
    expect(find.text('整理周报'), findsOneWidget);
    expect(find.text('要写文件'), findsOneWidget);
    expect(find.text('电脑 · 刚刚'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(TaskStatusChip), findsOneWidget);
  });

  testWidgets('running row shows spinner', (tester) async {
    final model = buildTaskListRowModel(
      status: TaskStatus.running,
      mode: ThreadMode.task,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListRowBody(
            title: '云端周报',
            model: model,
            statusLabel: '执行中',
            executorLabel: '云端',
            timeLabel: '1 分钟前',
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('执行中'), findsOneWidget);
  });
}
