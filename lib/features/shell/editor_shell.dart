/// 编辑器外壳：门控引擎启动、装配菜单/工具栏/停靠面板/状态栏、
/// 帧循环、快捷键、自动保存、拖放打开（AE0-1 ~ AE0-4）。
library;

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';

import '../../core/engine/engine_bootstrap.dart';
import '../../core/i18n/l10n.dart';
import '../../core/layout/dock_host.dart';
import '../../core/layout/dock_layout.dart';
import '../../core/shortcuts/shortcut_registry.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/engine_providers.dart';
import '../../core/state/project_controller.dart';
import '../../core/state/runtime_controller.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../project/project_actions.dart';
import 'editor_menu.dart';
import 'panel_registry.dart';
import 'shell_widgets.dart';
import 'start_page.dart';

/// 编辑器外壳。
class EditorShell extends ConsumerStatefulWidget {
  const EditorShell({super.key});

  @override
  ConsumerState<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends ConsumerState<EditorShell>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Timer? _autosaveTimer;
  Timer? _layoutTimer;
  Duration _sinceSave = Duration.zero;
  bool _layoutReady = false;
  bool _dragging = false;
  bool _forceEditor = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _autosaveTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _maybeAutosave(),
    );
    // 布局变化后防抖持久化。
    ref.listenManual<DockLayout?>(dockLayoutProvider, (previous, next) {
      if (!_layoutReady || next == null) return;
      _layoutTimer?.cancel();
      _layoutTimer = Timer(const Duration(milliseconds: 400), () {
        final json = ref.read(dockLayoutProvider.notifier).exportJson();
        if (json == null) return;
        ref
            .read(settingsProvider.notifier)
            .patch((settings) => settings.copyWith(layoutJson: json));
      });
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _autosaveTimer?.cancel();
    _layoutTimer?.cancel();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.5) return;
    final playback = ref.read(playbackProvider);
    if (!playback.playing) return;
    final time = ref.read(playbackProvider.notifier).advance(dt);
    ref.read(runtimeProvider.notifier).seek(time);
  }

  /// 让界面语言跟随设置（`system` 时用系统语言）。
  void _syncLocale(AppSettings settings) {
    final target = L10n.resolve(
      settings.localeCode,
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    if (context.locale == target) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.setLocale(target);
    });
  }

  void _maybeAutosave() {
    final settings = ref.read(settingsProvider).value;
    if (settings == null || settings.autosaveSeconds <= 0) return;
    _sinceSave += const Duration(seconds: 1);
    if (_sinceSave.inSeconds < settings.autosaveSeconds) return;
    _sinceSave = Duration.zero;
    final project = ref.read(projectProvider);
    if (!project.dirty || project.projectDir == null) return;
    ref.read(projectProvider.notifier).save();
  }

  void _ensureLayout(AppSettings settings) {
    if (_layoutReady) return;
    _layoutReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(dockLayoutProvider.notifier)
          .initialize(kEditorPanelSpecs, savedJson: settings.layoutJson);
    });
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(engineBootProvider);
    return boot.when(
      loading: () => const _Splash(),
      error: (error, stack) => _BootFailure(
        message: '$error',
        onRetry: () => ref.invalidate(engineBootProvider),
      ),
      data: (result) => _buildEditor(context, result),
    );
  }

  Widget _buildEditor(BuildContext context, EngineBootResult boot) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    _ensureLayout(settings);
    _syncLocale(settings);

    final project = ref.watch(projectProvider);
    final showStart = !project.hasProject && !_forceEditor;

    final handlers = <String, VoidCallback>{
      'file.new': () => ProjectActions.create(context, ref),
      'file.open': () => ProjectActions.open(context, ref),
      'file.save': () => ProjectActions.save(ref),
      'file.saveAs': () => ProjectActions.saveAs(context, ref),
      'file.export': () => ProjectActions.export(context, ref),
      'file.import': () => ProjectActions.import(context, ref),
      'edit.undo': () => ref.read(documentProvider.notifier).undo(),
      'edit.redo': () => ref.read(documentProvider.notifier).redo(),
      'edit.delete': () {
        final selection = ref.read(selectionProvider);
        if (selection.primary == null) return;
        ref.read(documentProvider.notifier).dispatch(
          'node.delete',
          <String, Object?>{'id': selection.primary},
        );
      },
      'edit.copy': () {},
      'edit.paste': () {},
      'view.fit': () => ref.read(viewportProvider.notifier).requestFit(),
      'view.zoomIn': () => ref
          .read(viewportProvider.notifier)
          .zoomAt(
            Offset(
              ref.read(viewportProvider).canvasSize.width / 2,
              ref.read(viewportProvider).canvasSize.height / 2,
            ),
            1.15,
          ),
      'view.zoomOut': () => ref
          .read(viewportProvider.notifier)
          .zoomAt(
            Offset(
              ref.read(viewportProvider).canvasSize.width / 2,
              ref.read(viewportProvider).canvasSize.height / 2,
            ),
            0.87,
          ),
      'view.flipX': () => ref.read(viewportProvider.notifier).toggleFlipX(),
      'view.flipY': () => ref.read(viewportProvider.notifier).toggleFlipY(),
      'view.toggleGrid': () => ref
          .read(settingsProvider.notifier)
          .patch((s) => s.copyWith(showGrid: !s.showGrid)),
      'motion.play': () {
        final runtime = ref.read(runtimeProvider);
        final controller = ref.read(runtimeProvider.notifier);
        if (runtime.playing) {
          controller.pause();
        } else if (runtime.motion != null) {
          controller.play(runtime.motion!);
        }
      },
      'motion.prevFrame': () => _stepFrames(-1),
      'motion.nextFrame': () => _stepFrames(1),
      'panel.left': () =>
          ref.read(dockLayoutProvider.notifier).toggleSlot(DockSlot.left),
      'panel.right': () =>
          ref.read(dockLayoutProvider.notifier).toggleSlot(DockSlot.right),
      'panel.bottom': () =>
          ref.read(dockLayoutProvider.notifier).toggleSlot(DockSlot.bottom),
      'panel.fullscreenCanvas': () {
        final layout = ref.read(dockLayoutProvider);
        if (layout == null) return;
        final sidesVisible =
            !(layout.hidden[DockSlot.left] ?? true) ||
            !(layout.hidden[DockSlot.right] ?? true);
        final controller = ref.read(dockLayoutProvider.notifier);
        if (sidesVisible) {
          if (!(layout.hidden[DockSlot.left] ?? true)) {
            controller.toggleSlot(DockSlot.left);
          }
          if (!(layout.hidden[DockSlot.right] ?? true)) {
            controller.toggleSlot(DockSlot.right);
          }
        } else {
          controller
            ..toggleSlot(DockSlot.left)
            ..toggleSlot(DockSlot.right);
        }
      },
    };

    return CallbackShortcuts(
      bindings: AmShortcuts.build(settings.shortcuts, handlers),
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) async {
            setState(() => _dragging = false);
            final files = details.files;
            if (files.isEmpty) return;
            final path = files.first.path;
            await ref.read(projectProvider.notifier).open(path);
          },
          child: Material(
            // 外壳是自绘的停靠布局，没有 Scaffold；而 MaterialApp 本身
            // **不提供** Material 祖先，所以这里必须显式给一个，
            // 否则树里所有 InkWell（SmallIconButton / ListRow …）都会抛
            // 「No Material widget found」。
            color: AppTheme.of(context).panelBackground,
            child: Column(
              children: <Widget>[
                const EditorMenuBar(),
                const EditorToolbar(),
                NoticeHost(boot: boot),
                Expanded(
                  child: showStart
                      ? StartPage(
                          onContinue: () => setState(() => _forceEditor = true),
                        )
                      : DockHost(builders: _builders, specs: kEditorPanelSpecs),
                ),
                const EditorStatusBar(),
                if (_dragging)
                  Container(
                    height: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _stepFrames(int direction) {
    final playback = ref.read(playbackProvider);
    final time = (playback.time + direction / 24).clamp(0.0, playback.duration);
    ref.read(playbackProvider.notifier).setTime(time);
    ref.read(runtimeProvider.notifier).seek(time);
  }

  static final Map<String, WidgetBuilder> _builders = buildPanelBuilders();
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.of(context).panelBackground,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('app.starting'.tr(), style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

class _BootFailure extends StatelessWidget {
  const _BootFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    return Scaffold(
      backgroundColor: tokens.panelBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 32, color: tokens.danger),
              const SizedBox(height: 12),
              Text(
                'engine.error.title'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: tokens.divider),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text('engine.error.retry'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
