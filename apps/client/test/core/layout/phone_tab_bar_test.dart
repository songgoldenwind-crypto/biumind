// phone_tab_bar 高亮判定测试。
//
// phoneTabIndexFor 是底部 tab 选中的核心逻辑 (路由前缀 → tab 索引),
// 改坏会让用户切到某页却高亮错的 tab。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:biumind/app/theme/theme.dart';
import 'package:biumind/core/layout/phone_tab_bar.dart';
import 'package:biumind/l10n/app_localizations.dart';

void main() {
  group('phoneTabIndexFor — 主 tab 精确匹配', () {
    test('5 个顶层目的地：任务 / 知识 / 创作 / 应用 / 我的', () {
      expect(phoneTabIndexFor('/chat'), 0, reason: '任务');
      expect(phoneTabIndexFor('/wiki'), 1, reason: '知识');
      expect(phoneTabIndexFor('/notes'), 1, reason: '笔记归知识');
      expect(phoneTabIndexFor('/creation'), 2, reason: '创作');
      expect(phoneTabIndexFor('/apps'), 3, reason: '应用');
      expect(phoneTabIndexFor('/profile'), 4, reason: '我的');
      expect(phoneTabIndexFor('/settings'), 4, reason: '我的伞下');
    });
  });

  group('phoneTabIndexFor — 子路径按前缀归 tab', () {
    test('模块内子页归上层 tab', () {
      expect(phoneTabIndexFor('/wiki/p/abc'), 1);
      expect(phoneTabIndexFor('/wiki/p/abc/pages/foo'), 1);
      expect(phoneTabIndexFor('/notes/trash'), 1);
      expect(phoneTabIndexFor('/creation/center'), 2);
      expect(phoneTabIndexFor('/creation/works/x'), 2);
      expect(phoneTabIndexFor('/apps/detail/foo'), 3);
      expect(phoneTabIndexFor('/apps/host/i1/home'), 3);
      expect(phoneTabIndexFor('/apps/installed'), 3);
      expect(phoneTabIndexFor('/apps/customize'), 3);
      expect(phoneTabIndexFor('/settings/devices'), 4);
    });
  });

  group('phoneTabIndexFor — 「我的」伞下三入口同归末位 tab', () {
    test('settings / membership / skills 都点亮我的', () {
      expect(phoneTabIndexFor('/membership'), 4);
      expect(phoneTabIndexFor('/membership/checkout'), 4);
      expect(phoneTabIndexFor('/membership/orders'), 4);
      expect(phoneTabIndexFor('/skills'), 4);
    });
  });

  group('phoneTabIndexFor — 无匹配兜底', () {
    test('横切 / 顶层独立路由兜底 tab 0 (任务)', () {
      expect(phoneTabIndexFor('/search'), 0);
      expect(phoneTabIndexFor('/suggestions'), 0);
      expect(phoneTabIndexFor('/splash'), 0);
      expect(phoneTabIndexFor('/login'), 0);
      expect(phoneTabIndexFor('/code'), 0);
    });
  });

  group('phoneTabIndexFor — 边界: 不误吞相近前缀', () {
    test('/wikifoo 不归知识 (实现用 path==prefix || startsWith(prefix/))', () {
      expect(phoneTabIndexFor('/chat'), 0);
      expect(phoneTabIndexFor('/wikifoo'), 0, reason: '兜底任务, 不误配知识');
    });
  });

  testWidgets('PhoneTabBar: 390 尺寸渲染 5 destination + 高亮任务',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: PhoneTabBar()),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      theme: buildTheme(
        palette: PaletteId.inkblueOrange,
        mode: Brightness.light,
        fontSize: FontSize.small,
      ),
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ));
    await tester.pump();
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('任务'), findsOneWidget, reason: 'tab1 navChat zh');
    expect(find.text('知识'), findsOneWidget, reason: 'tab2 知识含 wiki+笔记');
    expect(find.text('创作'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget, reason: '§12 应用不是应用中心');
    expect(find.text('笔记'), findsNothing);
    expect(find.text('我的'), findsOneWidget, reason: 'tab5');
  });
}
