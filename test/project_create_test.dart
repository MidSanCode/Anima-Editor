import 'dart:io';

import 'package:anima_editor/core/engine/am_engine.dart';
import 'package:anima_editor/core/state/engine_providers.dart';
import 'package:anima_editor/core/state/project_controller.dart';
import 'package:anima_editor/core/state/settings_controller.dart';
import 'package:anima_editor/core/state/ui_controllers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 新建工程相关的回归测试。
///
/// 守两条线：
///
/// 1. **`busy` 必须复位。** 之前六个工程方法只在 `on AmException` 里复位
///    `busy`，任何别的异常（插件未注册、写盘失败、目录取不到）逃逸之后
///    `busy` 永远是 true —— 界面上就是「一直转圈、一直加载」。
///    这是 Android 上真实踩到的现象。
/// 2. **落点解析失败要给出提示、不能静默。** 移动端取应用私有目录失败时
///    必须有可读反馈，而不是什么都不发生。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    container = ProviderContainer();
    await container.read(engineBootProvider.future);
    tmp = Directory.systemTemp.createTempSync('anima-create-');
  });

  tearDown(() {
    container.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  List<String> noticeKeys() =>
      container.read(notificationsProvider).map((n) => n.messageKey).toList();

  group('busy 复位', () {
    test('create 成功后会复位 busy', () async {
      final dir = '${tmp.path}${Platform.pathSeparator}p1';
      final ok = await container
          .read(projectProvider.notifier)
          .create(directory: dir, name: 'm1');
      expect(ok, isTrue);
      expect(container.read(projectProvider).busy, isFalse);
    });

    test('create 失败（目录已有工程）后会复位 busy', () async {
      final dir = '${tmp.path}${Platform.pathSeparator}p2';
      final notifier = container.read(projectProvider.notifier);
      expect(await notifier.create(directory: dir, name: 'm2'), isTrue);
      // 同一个目录再建一次 -> PROJECT_EXISTS
      expect(await notifier.create(directory: dir, name: 'm3'), isFalse);
      expect(
        container.read(projectProvider).busy,
        isFalse,
        reason: 'PROJECT_EXISTS 之后界面不该继续转圈',
      );
    });

    test('open 失败后会复位 busy', () async {
      final missing = '${tmp.path}${Platform.pathSeparator}does-not-exist';
      final notifier = container.read(projectProvider.notifier);
      await notifier.open(missing);
      expect(
        container.read(projectProvider).busy,
        isFalse,
        reason: '打开不存在的工程之后不该卡在加载态',
      );
    });

    test('validate 在无工程时失败也会复位 busy', () async {
      await container.read(projectProvider.notifier).validate();
      expect(container.read(projectProvider).busy, isFalse);
    });

    test('export 在无工程时失败也会复位 busy', () async {
      await container.read(projectProvider.notifier).export();
      expect(container.read(projectProvider).busy, isFalse);
    });
  });

  group('新建工程落点', () {
    test('桌面端不给目录时给出明确提示，且不静默失败', () async {
      // 测试跑在桌面环境：WorkspaceDirectory.usesAppPrivateStorage 为 false，
      // 因此 create(directory: null) 应当拒绝并提示。
      final ok = await container.read(projectProvider.notifier).create(
            name: 'no-dir',
          );
      expect(ok, isFalse);
      expect(container.read(projectProvider).busy, isFalse);
      // 提示必须存在，不能什么都没有。
      expect(noticeKeys(), isNotEmpty);
    });

    test('create 后工程状态被正确设置', () async {
      final dir = '${tmp.path}${Platform.pathSeparator}p9';
      await container
          .read(projectProvider.notifier)
          .create(directory: dir, name: 'model9');
      final state = container.read(projectProvider);
      expect(state.name, 'model9');
      expect(state.sourceKind, 'directory');
      expect(state.projectDir, isNotNull);
      expect(state.busy, isFalse);
    });
  });
}
