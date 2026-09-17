import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/task_workdir.dart';

void main() {
  test('phone and web must not pick a computer disk', () {
    expect(
      canPickComputerWorkdir(isWeb: true, platform: TargetPlatform.macOS),
      isFalse,
    );
    expect(
      canPickComputerWorkdir(isWeb: false, platform: TargetPlatform.iOS),
      isFalse,
    );
    expect(
      canPickComputerWorkdir(isWeb: false, platform: TargetPlatform.android),
      isFalse,
    );
  });

  test('desktop can pick a local folder', () {
    expect(
      canPickComputerWorkdir(isWeb: false, platform: TargetPlatform.macOS),
      isTrue,
    );
    expect(
      canPickComputerWorkdir(isWeb: false, platform: TargetPlatform.windows),
      isTrue,
    );
    expect(
      canPickComputerWorkdir(isWeb: false, platform: TargetPlatform.linux),
      isTrue,
    );
  });
}
