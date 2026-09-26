/// 外壳渲染回归测试。
///
/// 覆盖两个此前完全没有测试的缺陷：
/// 1. 主 shell 的根没有 Scaffold / Material（MaterialApp 本身**不提供**
///    Material 祖先），树里所有 InkWell 抛「No Material widget found」，
///    被 ErrorWidget.builder 换成降级提示块；
/// 2. 启动页两处 RenderFlex 溢出（标题 Row 右溢、动作卡片固定高度下溢）。
///
/// 注意：easy_localization 是全局单例，同一测试进程里起多个
/// AnimaEditorApp 实例会互相干扰，因此本文件只放这一个测试；
/// 需要独立起 app 的用例请另建文件。
library;

import 'dart:convert';

import 'package:anima_editor/app.dart';
import 'package:anima_editor/core/i18n/l10n.dart';
import 'package:anima_editor/features/shell/start_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 反复 pump 直到 [ready] 成立，避免依赖固定时长而空过断言。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 60,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _expectNoException(WidgetTester tester, String stage) {
  final error = tester.takeException();
  expect(error, isNull, reason: '$stage 出现异常：$error');
}

void _expectAllInkWellsHaveMaterial(WidgetTester tester, String stage) {
  final inkWells = find.byType(InkWell).evaluate().toList();
  expect(
    inkWells,
    isNotEmpty,
    reason: '$stage 没有找到任何 InkWell —— 断言会空过，说明页面没渲染出来',
  );
  for (final element in inkWells) {
    expect(
      element.findAncestorWidgetOfExactType<Material>(),
      isNotNull,
      reason: '$stage 中 ${element.widget} 缺少 Material 祖先',
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // easy_localization 的 ensureInitialized / saveLocale 会走
    // shared_preferences，测试环境没有插件实现，这里给个空的内存实现。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (MethodCall call) async =>
              call.method == 'getAll' ? <String, Object>{} : null,
        );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('外壳：启动页 → 编辑器，无异常且 InkWell 都有 Material 祖先', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: EasyLocalization(
          supportedLocales: L10n.supportedLocales,
          path: 'assets/translations',
          fallbackLocale: L10n.fallbackLocale,
          useOnlyLangCode: false,
          child: const AnimaEditorApp(),
        ),
      ),
    );

    // ---- 启动页 ----
    await _pumpUntil(
      tester,
      () => find.byType(StartPage).evaluate().isNotEmpty,
    );
    expect(find.byType(StartPage), findsOneWidget, reason: '引擎启动后应进入启动页');
    _expectNoException(tester, '启动页');
    _expectAllInkWellsHaveMaterial(tester, '启动页');

    // ---- 进入编辑器（点「示例工程」卡片 → onContinue → 停靠编辑器）----
    final en =
        jsonDecode(
              await rootBundle.loadString('assets/translations/en-US.json'),
            )
            as Map<String, dynamic>;
    final zh =
        jsonDecode(
              await rootBundle.loadString('assets/translations/zh-CN.json'),
            )
            as Map<String, dynamic>;
    final sampleLabel = <String>[
      if (en['start.sample'] is String) en['start.sample'] as String,
      if (zh['start.sample'] is String) zh['start.sample'] as String,
    ];
    final target = find.byWidgetPredicate(
      (w) => w is Text && w.data != null && sampleLabel.contains(w.data),
    );
    expect(target, findsWidgets, reason: '应能找到示例工程入口');
    await tester.tap(target.first);

    await _pumpUntil(tester, () => find.byType(StartPage).evaluate().isEmpty);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(StartPage), findsNothing, reason: '应已切到编辑器');
    _expectNoException(tester, '编辑器');
    _expectAllInkWellsHaveMaterial(tester, '编辑器');
  });
}
