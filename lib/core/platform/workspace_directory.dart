/// 工程工作区目录解析（移动端专用）。
///
/// ## 为什么需要这个
///
/// 「新建工程」原来的流程是**先让用户挑一个目录**，再往里面写工程。
/// 这在桌面上成立，在 Android / iOS 上不成立：
///
/// * 两个平台的目录选择器走系统选择器，Android 侧**默认只给只读授权**
///   （`AndroidSAFOptions.accessMode` 默认 `readOnly`），而我们紧接着要往
///   那个目录里写 `info.json` / `registry.json` / `spec/`，写入会被拒；
/// * 更要命的是系统选择器返回的是 `content://` URI，不是文件系统路径。
///   原生侧解析不出真实路径时返回 `null`，于是流程在第一步就断掉。
/// * iOS 的沙盒同样不允许往任意路径写。
///
/// 结论：移动端不该让用户挑目录。新建工程一律落在**应用私有目录**下 ——
/// 那是两个平台都保证可读写、且不需要任何权限的地方。用户想放到别处，
/// 走「导出 / 另存为」（导出是写一个文件，系统选择器支持）。
///
/// 桌面端的「挑目录」流程保持不变：那边没有沙盒和 SAF 的限制，
/// 让用户自己选位置是合理的。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 工作区目录解析器。
class WorkspaceDirectory {
  const WorkspaceDirectory._();

  /// 工程在私有目录下的子目录名。
  static const String folderName = 'projects';

  /// 当前平台是否应当**跳过目录选择器**、改用应用私有目录。
  ///
  /// Web 端本来就不支持目录模式（`AmFileSystem.supportsDirectories` 为 false），
  /// 走不到这里；这里只判断移动端。
  static bool get usesAppPrivateStorage {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 取工程工作区根目录。
  ///
  /// 取不到时抛异常 —— 调用方负责转成用户可读的提示，
  /// **不要**悄悄退回到「随便挑个目录」，那正是移动端坏掉的原因。
  static Future<String> root() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// 为某个工程名生成一个**尚不存在**的目录路径。
  ///
  /// 同名时依次尝试 `name-2`、`name-3`……这样「新建同名工程」不会撞上
  /// 引擎的 `PROJECT_EXISTS`，用户也不必先手动删掉旧的。
  static Future<String> allocate(String name) async {
    final parent = await root();
    var candidate = p.join(parent, name);
    var n = 2;
    while (await Directory(candidate).exists() ||
        await File(candidate).exists()) {
      candidate = p.join(parent, '$name-$n');
      n += 1;
    }
    return candidate;
  }
}
