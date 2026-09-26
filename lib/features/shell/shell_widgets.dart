/// 外壳组件：通知横幅、工具栏、状态栏。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/engine_bootstrap.dart';
import '../../core/i18n/l10n.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/engine_providers.dart';
import '../../core/state/project_controller.dart';
import '../../core/state/runtime_controller.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

/// 通知 + 引擎告警 + 忙碌进度（A0-4：引擎不可用时必须给出可读反馈）。
class NoticeHost extends ConsumerWidget {
  const NoticeHost({super.key, required this.boot});

  final EngineBootResult boot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final notices = ref.watch(notificationsProvider);
    final project = ref.watch(projectProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (boot.warningKey != null)
          _Banner(
            icon: Icons.extension_off,
            color: tokens.warning,
            titleKey: boot.warningKey!,
            message: boot.notes.isEmpty
                ? null
                : boot.notes.entries
                      .map((entry) => '${entry.key}=${entry.value}')
                      .join(' · '),
            onDismiss: null,
          ),
        for (final notice in notices)
          _Banner(
            icon: switch (notice.level) {
              NoticeLevel.success => Icons.check_circle_outline,
              NoticeLevel.warning => Icons.warning_amber,
              NoticeLevel.error => Icons.error_outline,
              NoticeLevel.info => Icons.info_outline,
            },
            color: switch (notice.level) {
              NoticeLevel.success => tokens.accentSecondary,
              NoticeLevel.warning => tokens.warning,
              NoticeLevel.error => tokens.danger,
              NoticeLevel.info => tokens.divider,
            },
            titleKey: notice.messageKey,
            args: notice.args,
            message: notice.detail,
            onDismiss: () => ref
                .read(notificationsProvider.notifier)
                .dismiss(notice.id ?? ''),
          ),
        if (project.busy)
          LinearProgressIndicator(
            minHeight: 2,
            value: project.progress,
            backgroundColor: tokens.divider,
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.titleKey,
    this.args = const <String, String>{},
    this.message,
    this.onDismiss,
  });

  final IconData icon;
  final Color color;
  final String titleKey;
  final Map<String, String> args;
  final String? message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  titleKey.tr(namedArgs: args),
                  style: const TextStyle(fontSize: 11.5),
                ),
                if (message != null && message!.isNotEmpty)
                  Text(
                    message!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: tokens.divider),
                  ),
              ],
            ),
          ),
          if (onDismiss != null)
            SmallIconButton(
              icon: Icons.close,
              tooltipKey: 'common.close',
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

/// 工具栏：工具切换、编辑、视图、播放。
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final tool = ref.watch(toolProvider);
    final document = ref.watch(documentProvider);
    final runtime = ref.watch(runtimeProvider);
    final viewport = ref.watch(viewportProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: tokens.panelHeader,
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: <Widget>[
          for (final entry in <EditorTool, (IconData, String)>{
            EditorTool.select: (Icons.near_me, 'tool.select'),
            EditorTool.vertex: (Icons.grain, 'tool.vertex'),
            EditorTool.deformer: (Icons.architecture, 'tool.deformer'),
          }.entries)
            SmallIconButton(
              icon: entry.value.$1,
              tooltipKey: entry.value.$2,
              selected: tool == entry.key,
              onPressed: () =>
                  ref.read(toolProvider.notifier).setTool(entry.key),
            ),
          _divider(tokens),
          SmallIconButton(
            icon: Icons.undo,
            tooltipKey: 'edit.undo',
            onPressed: document.canUndo
                ? () => ref.read(documentProvider.notifier).undo()
                : null,
          ),
          SmallIconButton(
            icon: Icons.redo,
            tooltipKey: 'edit.redo',
            onPressed: document.canRedo
                ? () => ref.read(documentProvider.notifier).redo()
                : null,
          ),
          _divider(tokens),
          SmallIconButton(
            icon: Icons.grid_4x4,
            tooltipKey: 'canvas.toggleGrid',
            selected: settings.showGrid,
            onPressed: () => ref
                .read(settingsProvider.notifier)
                .patch((s) => s.copyWith(showGrid: !s.showGrid)),
          ),
          SmallIconButton(
            icon: Icons.fit_screen,
            tooltipKey: 'canvas.fit',
            onPressed: () => ref.read(viewportProvider.notifier).requestFit(),
          ),
          SmallIconButton(
            icon: Icons.zoom_in,
            tooltipKey: 'canvas.zoomIn',
            onPressed: () => ref
                .read(viewportProvider.notifier)
                .zoomAt(
                  Offset(
                    viewport.canvasSize.width / 2,
                    viewport.canvasSize.height / 2,
                  ),
                  1.15,
                ),
          ),
          SmallIconButton(
            icon: Icons.zoom_out,
            tooltipKey: 'canvas.zoomOut',
            onPressed: () => ref
                .read(viewportProvider.notifier)
                .zoomAt(
                  Offset(
                    viewport.canvasSize.width / 2,
                    viewport.canvasSize.height / 2,
                  ),
                  0.87,
                ),
          ),
          const Spacer(),
          SmallIconButton(
            icon: runtime.playing ? Icons.pause : Icons.play_arrow,
            tooltipKey: runtime.playing ? 'motion.pause' : 'motion.play',
            onPressed: () {
              final controller = ref.read(runtimeProvider.notifier);
              if (runtime.playing) {
                controller.pause();
              } else if (runtime.motion != null) {
                controller.play(runtime.motion!);
              }
            },
          ),
          SmallIconButton(
            icon: Icons.fiber_manual_record,
            tooltipKey: 'motion.record',
            selected: ref.watch(playbackProvider).recording,
            onPressed: () {
              final playback = ref.read(playbackProvider);
              ref
                  .read(playbackProvider.notifier)
                  .setRecording(!playback.recording);
            },
          ),
        ],
      ),
    );
  }

  Widget _divider(AppTokens tokens) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: tokens.divider,
  );
}

/// 状态栏：工程、修订、后端、缩放、提示。
class EditorStatusBar extends ConsumerWidget {
  const EditorStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final project = ref.watch(projectProvider);
    final document = ref.watch(documentProvider);
    final viewport = ref.watch(viewportProvider);
    final runtime = ref.watch(runtimeProvider);
    final status = ref.watch(engineStatusProvider);

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tokens.panelHeader,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            project.dirty ? Icons.circle : Icons.check_circle,
            size: 10,
            color: project.dirty ? tokens.warning : tokens.accentSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            project.name == null
                ? 'status.noProject'.tr()
                : '${project.name}${project.dirty ? ' *' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
          _gap(),
          Text(
            'status.revision'.tr(
              namedArgs: <String, String>{'value': '${document.revision}'},
            ),
            style: TextStyle(fontSize: 10.5, color: tokens.divider),
          ),
          _gap(),
          Text(
            'status.backend'.tr(
              namedArgs: <String, String>{'value': status.backend.label.tr()},
            ),
            style: TextStyle(fontSize: 10.5, color: tokens.divider),
          ),
          if (runtime.motion != null) ...<Widget>[
            _gap(),
            Text(
              'status.motion'.tr(
                namedArgs: <String, String>{
                  'name': runtime.motion!,
                  'time': Fmt.duration(runtime.time),
                },
              ),
              style: TextStyle(fontSize: 10.5, color: tokens.divider),
            ),
          ],
          const Spacer(),
          Text(
            'status.zoom'.tr(
              namedArgs: <String, String>{
                'value': viewport.zoom.toStringAsFixed(2),
              },
            ),
            style: TextStyle(fontSize: 10.5, color: tokens.divider),
          ),
          _gap(),
          Text(
            'status.nodes'.tr(
              namedArgs: <String, String>{'value': '${document.nodes.length}'},
            ),
            style: TextStyle(fontSize: 10.5, color: tokens.divider),
          ),
        ],
      ),
    );
  }

  Widget _gap() => const SizedBox(width: 14);
}
