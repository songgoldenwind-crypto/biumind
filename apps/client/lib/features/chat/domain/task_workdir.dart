import 'package:flutter/foundation.dart';

/// 不在手机上弹系统目录选择器：手机选不了电脑磁盘。
bool canPickComputerWorkdir({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return false;
  switch (platform) {
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return true;
    default:
      return false;
  }
}
