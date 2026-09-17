import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/task_expert.dart';

void main() {
  test('expert title uses role and parent task name', () {
    expect(
      expertTaskTitle(role: '法务', parentTitle: '整理周报'),
      '法务 · 整理周报',
    );
  });

  test('empty role still marks the child as an expert', () {
    expect(expertTaskTitle(role: '  ', parentTitle: ''), '专家 · 任务');
  });
}
