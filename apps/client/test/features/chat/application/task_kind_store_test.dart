import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/application/task_kind_store.dart';
import 'package:biumind/features/chat/domain/task_kind.dart';

void main() {
  test('remember keeps office when later sync has no kind', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(taskKindMapProvider.notifier);
    n.remember('t1', kTaskKindOffice);
    n.remember('t1', null);
    n.remember('t1', '');
    expect(n.kindOf('t1'), kTaskKindOffice);
  });

  test('remote kind overwrites local default', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(taskKindMapProvider.notifier);
    n.remember('t1', kTaskKindGeneral);
    n.remember('t1', kTaskKindCode);
    expect(n.kindOf('t1'), kTaskKindCode);
  });
}
