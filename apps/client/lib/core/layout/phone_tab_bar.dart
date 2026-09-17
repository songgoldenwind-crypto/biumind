// 移动端底部主导航。
//
// 5 个高频 tab 与桌面主栏同一份 kPrimaryNav：任务 / 知识 / 创作 / 应用 / 我的。
// 编码走 /code，不进底栏。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import 'primary_nav.dart';

int phoneTabIndexFor(String path) => primaryNavIndexFor(path);

/// 手机形态底部主导航。挂载点: `_AppShell` phone 分支 body Column 末尾。
/// tab0 现为任务首页（原「对话」）。
///
/// 用 Material 3 [NavigationBar] (a11y / ripple / label 行为自带), 选中态
/// 经局部 [NavigationBarTheme] 套品牌色 (跟桌面 `_NavRow` selected =
/// brand / brandSoft 视觉一致), 不污染全局主题。
class PhoneTabBar extends StatelessWidget {
  const PhoneTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final c = Theme.of(context).extension<BiuColors>()!;
    final loc = GoRouterState.of(context).uri.path;
    final selectedIndex = phoneTabIndexFor(loc);

    return SafeArea(
      // top:false — 主壳外层 SafeArea(top:phone) 已吃顶部 inset; 这里只
      // 让出底部 home indicator 区。放 Column 末尾 (非 Scaffold 的
      // bottomNavigationBar 槽), 必须自己处理 bottom inset。
      top: false,
      child: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: c.surface0,
            surfaceTintColor: Colors.transparent,
            indicatorColor: c.brandSoft,
            height: 60,
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                  color: selected ? c.brand : c.text3, size: 22);
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                color: selected ? c.brand : c.text3,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              );
            }),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => context.go(kPrimaryNav[i].path),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final dest in kPrimaryNav)
              NavigationDestination(
                icon: Icon(primaryNavIcons(dest.id).$1),
                selectedIcon: Icon(primaryNavIcons(dest.id).$2),
                label: primaryNavLabel(t, dest.id),
              ),
          ],
        ),
      ),
    );
  }
}
