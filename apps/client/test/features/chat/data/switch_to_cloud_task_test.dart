import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/data/local/db.dart';
import 'package:biumind/features/chat/data/chat_repo.dart';
import 'package:biumind/features/chat/domain/chat_models.dart';

void main() {
  late AppDb db;
  late ChatRepo repo;

  setUp(() {
    db = AppDb.memory();
    repo = ChatRepo(db, scope: 'test-scope');
  });
  tearDown(() async {
    await db.close();
  });

  test('switchToCloudTask sets mode=task and runtimeEnvMode=cloud', () async {
    await repo.createThread(
      id: 't1',
      mode: ThreadMode.agent,
      environmentId: 'env-1',
      runtimeEnvMode: 'local',
    );
    await repo.switchToCloudTask('t1');
    final t = await repo.getThread('t1');
    expect(t!.mode, ThreadMode.task);
    expect(t.runtimeEnvMode, 'cloud');
  });
}
