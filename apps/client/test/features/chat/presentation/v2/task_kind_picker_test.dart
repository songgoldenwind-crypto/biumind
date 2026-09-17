import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/task_kind.dart';
import 'package:biumind/features/chat/presentation/v2/task_kind_picker.dart';
import 'package:biumind/l10n/app_localizations.dart';

void main() {
  testWidgets('kind picker offers general / office / code', (tester) async {
    var kind = kTaskKindGeneral;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => TaskKindPicker(
            kind: kind,
            onChanged: (v) => setState(() => kind = v),
          ),
        ),
      ),
    ));
    expect(find.text('任务类型'), findsOneWidget);
    expect(find.text('通用'), findsOneWidget);
    expect(find.text('办公'), findsOneWidget);
    expect(find.text('编码'), findsOneWidget);
    await tester.tap(find.text('办公'));
    await tester.pumpAndSettle();
    expect(kind, kTaskKindOffice);
  });
}
