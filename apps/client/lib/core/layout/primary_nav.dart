import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 外层主导航：任务 / 知识 / 创作 / 应用 / 我的。编码走 /code，不进主栏。
class PrimaryNavDest {
  final String id;
  final String path;
  final List<String> matches;

  const PrimaryNavDest(this.id, this.path, this.matches);
}

const kPrimaryNav = <PrimaryNavDest>[
  PrimaryNavDest('chat', '/chat', ['/chat']),
  PrimaryNavDest('wiki', '/wiki', ['/wiki', '/notes']),
  PrimaryNavDest('creation', '/creation', ['/creation']),
  PrimaryNavDest('apps', '/apps', ['/apps']),
  PrimaryNavDest('profile', '/profile', [
    '/profile',
    '/settings',
    '/membership',
    '/skills',
  ]),
];

int primaryNavIndexFor(String path) {
  for (var i = 0; i < kPrimaryNav.length; i++) {
    for (final prefix in kPrimaryNav[i].matches) {
      if (path == prefix || path.startsWith('$prefix/')) return i;
    }
  }
  return 0;
}

bool primaryNavMatches(String current, String itemPath, {List<String>? also}) {
  if (current == itemPath || current.startsWith('$itemPath/')) return true;
  if (also == null) return false;
  for (final prefix in also) {
    if (current == prefix || current.startsWith('$prefix/')) return true;
  }
  return false;
}

List<String>? primaryNavAlsoMatch(PrimaryNavDest d) {
  final extra = [for (final m in d.matches) if (m != d.path) m];
  return extra.isEmpty ? null : extra;
}

String primaryNavLabel(AppLocalizations t, String id) => switch (id) {
      'chat' => t.navChat,
      'wiki' => t.navWiki,
      'creation' => t.navCreation,
      'apps' => t.navApps,
      'profile' => t.navProfile,
      _ => id,
    };

(IconData outline, IconData selected) primaryNavIcons(String id) => switch (id) {
      'chat' => (Icons.assignment_outlined, Icons.assignment_rounded),
      'wiki' => (Icons.menu_book_outlined, Icons.menu_book_rounded),
      'creation' => (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
      'apps' => (Icons.apps_outlined, Icons.apps_rounded),
      'profile' => (Icons.person_outline_rounded, Icons.person_rounded),
      _ => (Icons.circle_outlined, Icons.circle),
    };
