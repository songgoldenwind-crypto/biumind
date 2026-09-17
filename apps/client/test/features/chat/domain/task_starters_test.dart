import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/task_starters.dart';

void main() {
  test('task starters are office deliverables, not chat icebreakers', () {
    expect(kTaskStarters.length, greaterThanOrEqualTo(4));
    final titles = kTaskStarters.map((s) => s.title).join(' ');
    expect(titles, isNot(contains('帮我写一段文案')));
    expect(titles, isNot(contains('解释一个概念')));
    expect(kTaskStarters.every((s) => s.prompt.trim().isNotEmpty), isTrue);
    expect(
      kTaskStarters.any((s) => s.prompt.contains('周报') || s.title.contains('周报')),
      isTrue,
    );
    expect(
      kTaskStarters.every((s) => s.kind == 'office'),
      isTrue,
    );
  });
}
