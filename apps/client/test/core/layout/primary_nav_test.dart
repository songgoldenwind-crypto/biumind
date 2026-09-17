import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/core/layout/primary_nav.dart';

void main() {
  test('primary nav is 任务 / 知识 / 创作 / 应用 / 我的', () {
    expect(kPrimaryNav.map((d) => d.id).toList(), [
      'chat',
      'wiki',
      'creation',
      'apps',
      'profile',
    ]);
    expect(kPrimaryNav.map((d) => d.path).toList(), [
      '/chat',
      '/wiki',
      '/creation',
      '/apps',
      '/profile',
    ]);
  });

  test('知识 matches wiki and notes; 我的 matches settings umbrella', () {
    expect(primaryNavIndexFor('/wiki/p/abc'), 1);
    expect(primaryNavIndexFor('/notes/trash'), 1);
    expect(primaryNavIndexFor('/creation/works'), 2);
    expect(primaryNavIndexFor('/apps'), 3);
    expect(primaryNavIndexFor('/settings/devices'), 4);
    expect(primaryNavIndexFor('/skills'), 4);
    expect(primaryNavIndexFor('/code'), 0, reason: '编码不是主栏，兜底任务');
  });

  test('desktop alsoMatch is derived from kPrimaryNav', () {
    expect(primaryNavAlsoMatch(kPrimaryNav[1]), ['/notes']);
    expect(primaryNavAlsoMatch(kPrimaryNav[4]), [
      '/settings',
      '/membership',
      '/skills',
    ]);
    expect(primaryNavAlsoMatch(kPrimaryNav[0]), isNull);
  });
}
