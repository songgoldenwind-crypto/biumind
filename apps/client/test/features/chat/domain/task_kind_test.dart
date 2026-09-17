import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/task_kind.dart';

void main() {
  test('empty or unknown kind is general', () {
    expect(normalizeTaskKind(null), kTaskKindGeneral);
    expect(normalizeTaskKind(''), kTaskKindGeneral);
    expect(normalizeTaskKind('whatever'), kTaskKindGeneral);
  });

  test('office and code kinds are accepted', () {
    expect(normalizeTaskKind('office'), kTaskKindOffice);
    expect(normalizeTaskKind('CODE'), kTaskKindCode);
  });

  test('kind=code deep-links to the code workbench', () {
    expect(shouldDeepLinkCodeWorkbench('code'), isTrue);
    expect(shouldDeepLinkCodeWorkbench('office'), isFalse);
    expect(shouldDeepLinkCodeWorkbench(null), isFalse);
  });

  test('office result pane hides git/terminal tools', () {
    expect(officeResultHidesCodeTools('office'), isTrue);
    expect(officeResultHidesCodeTools('general'), isFalse);
    expect(isCodeWorkbenchToolName('Bash'), isTrue);
    expect(isCodeWorkbenchToolName('git_status'), isTrue);
    expect(isCodeWorkbenchToolName('Write'), isFalse);
  });
}
