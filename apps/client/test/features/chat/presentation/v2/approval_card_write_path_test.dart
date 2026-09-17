import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/application/chat_controller.dart';
import 'package:biumind/features/chat/data/biu_session_connection.dart';
import 'package:biumind/features/chat/presentation/v2/approval_card.dart';
import 'package:biumind/l10n/app_localizations.dart';

class _SeedApprovals extends PendingApprovalsController {
  @override
  PendingApprovalsState build() => PendingApprovalsState(byThread: {
        't1': [
          PermissionRequested(
            requestId: 'r1',
            toolName: 'Write',
            toolUseId: 'u1',
            input: {
              'path': '/tmp/week.md',
              'contents': 'hello',
              'encoding': 'utf-8',
              'create': true,
              'overwrite': true,
            },
            respond: ({required allow}) {},
          ),
        ],
      });
}

void main() {
  testWidgets('Write approval shows path without expanding JSON',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pendingApprovalsProvider.overrideWith(_SeedApprovals.new),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ApprovalCardV2(threadId: 't1')),
      ),
    ));
    expect(find.text('将写入：/tmp/week.md'), findsOneWidget);
    expect(find.textContaining('展开完整入参'), findsOneWidget);
  });
}
