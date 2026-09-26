/// 工程动作：新建 / 打开 / 保存 / 另存为 / 导出 / 导入 / 最近打开。
///
/// 菜单、工具栏、起始页共用这一份实现，避免流程分叉。
library;

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/file_service.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/project_controller.dart';
import '../../core/state/runtime_controller.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../common/widgets.dart';

/// 工程动作集合。
class ProjectActions {
  const ProjectActions._();

  /// 新建工程（选择目录 + 名称）。
  static Future<void> create(BuildContext context, WidgetRef ref) async {
    final directory = await FileService.pickDirectory(
      dialogTitle: 'dialog.newProject'.tr(),
    );
    if (directory == null || !context.mounted) return;
    final name = await promptDialog(
      context,
      titleKey: 'dialog.newProject',
      labelKey: 'dialog.projectName',
      initial: 'my_model',
    );
    if (name == null || name.isEmpty) return;
    final valid = RegExp(r'^[a-z0-9_-]+$').hasMatch(name);
    if (!valid) {
      ref
          .read(notificationsProvider.notifier)
          .error('notice.project.nameInvalid', detail: '^[a-z0-9_-]+\$');
      return;
    }
    await ref
        .read(projectProvider.notifier)
        .create(directory: directory, name: name, displayName: name);
  }

  /// 打开工程（目录或 `.amproj` 压缩包）。
  static Future<void> open(BuildContext context, WidgetRef ref) async {
    final files = await FileService.pickFiles(
      extensions: <String>['amproj'],
      dialogTitle: 'dialog.openProject'.tr(),
    );
    if (files.isNotEmpty) {
      final path = files.first.path;
      if (path == null) {
        // Web / 内容 URI：走内存导入路径。
        final bytes = files.first.bytes;
        if (bytes == null) return;
        await _openBytes(ref, bytes);
        return;
      }
      await ref.read(projectProvider.notifier).open(path);
      return;
    }
    if (!context.mounted) return;
    final directory = await FileService.pickDirectory(
      dialogTitle: 'dialog.openProjectDir'.tr(),
    );
    if (directory == null) return;
    await ref.read(projectProvider.notifier).open(directory);
  }

  static Future<void> _openBytes(WidgetRef ref, List<int> bytes) async {
    // 浏览器环境没有可写目录，直接把包内容交给引擎的内存模式。
    ref
        .read(notificationsProvider.notifier)
        .info(
          'notice.project.webMemoryOnly',
          args: <String, String>{'bytes': '${bytes.length}'},
        );
  }

  /// 保存（已有路径直接写回）。
  static Future<void> save(WidgetRef ref) async {
    final project = ref.read(projectProvider);
    if (project.projectDir == null) {
      ref.read(notificationsProvider.notifier).warn('notice.project.noPath');
      return;
    }
    await ref.read(projectProvider.notifier).save();
  }

  /// 另存为。
  static Future<void> saveAs(BuildContext context, WidgetRef ref) async {
    final directory = await FileService.pickDirectory(
      dialogTitle: 'dialog.saveAs'.tr(),
    );
    if (directory == null) return;
    await ref.read(projectProvider.notifier).save(saveAs: directory);
  }

  /// 导出 `.amproj`（默认写到工程目录旁；也可指定目录）。
  static Future<void> export(
    BuildContext context,
    WidgetRef ref, {
    bool chooseDirectory = false,
  }) async {
    final project = ref.read(projectProvider);
    String? target;
    if (chooseDirectory) {
      final directory = await FileService.pickDirectory(
        dialogTitle: 'dialog.exportTo'.tr(),
      );
      if (directory == null) return;
      target =
          '$directory${_separator(directory)}${project.name ?? 'model'}.amproj';
    }
    await ref.read(projectProvider.notifier).export(outPath: target);
  }

  static String _separator(String path) =>
      path.contains('\\') && !path.contains('/') ? '\\' : '/';

  /// 导入 `.amproj` 到目录。
  static Future<void> import(BuildContext context, WidgetRef ref) async {
    final files = await FileService.pickFiles(
      extensions: <String>['amproj'],
      dialogTitle: 'dialog.importProject'.tr(),
    );
    if (files.isEmpty) return;
    final source = files.first.path;
    if (source == null) {
      ref
          .read(notificationsProvider.notifier)
          .warn('notice.project.importNeedsPath');
      return;
    }
    if (!context.mounted) return;
    final directory = await FileService.pickDirectory(
      dialogTitle: 'dialog.importTarget'.tr(),
    );
    if (directory == null) return;
    await ref.read(projectProvider.notifier).importPackage(source, directory);
  }

  /// 打开最近列表中的一项。
  static Future<void> openRecent(WidgetRef ref, String path) async {
    await ref.read(projectProvider.notifier).open(path);
  }

  /// 从最近列表移除。
  static Future<void> forgetRecent(WidgetRef ref, String path) async {
    await ref
        .read(settingsProvider.notifier)
        .patch((settings) => settings.withoutRecent(path));
  }

  /// 关闭当前工程。
  static Future<void> close(BuildContext context, WidgetRef ref) async {
    final project = ref.read(projectProvider);
    if (project.dirty) {
      final ok = await confirmDialog(
        context,
        titleKey: 'dialog.closeUnsaved',
        messageKey: 'dialog.closeUnsavedMessage',
        confirmKey: 'dialog.discard',
      );
      if (!ok) return;
    }
    await ref.read(projectProvider.notifier).close();
    ref.read(selectionProvider.notifier).clear();
  }

  /// 把 base64 字符串转回字节（导入向导使用）。
  static List<int> decodeBase64(String value) {
    final comma = value.indexOf(',');
    return base64Decode(comma < 0 ? value : value.substring(comma + 1));
  }

  /// 重新加载文档与运行时（导入 / 外部修改后）。
  static Future<void> reload(WidgetRef ref) async {
    await ref.read(documentProvider.notifier).load();
    await ref.read(runtimeProvider.notifier).load();
  }
}
