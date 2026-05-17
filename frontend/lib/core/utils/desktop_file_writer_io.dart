import 'dart:io';

import 'package:flutter/foundation.dart';

/// 在桌面平台（Windows / Linux / macOS）上 file_picker.saveFile 只返回路径，
/// 不会写入字节内容；需要调用方自行写盘。
/// 移动平台（Android / iOS）由 file_picker 内部通过 SAF / share 完成写入，此处跳过。
Future<void> ensureFileWritten(String path, Uint8List bytes) async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      await File(path).writeAsBytes(bytes);
      break;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      // 由 file_picker 自行写入
      break;
  }
}
