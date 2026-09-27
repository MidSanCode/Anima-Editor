/// 画布：引擎纹理（可用时）或降级绘制，加完整视图交互与编辑手势。
///
/// AE2-1 视图：平移 / 缩放 / 适应 / 翻转 / 网格 / 参考线 / 洋葱皮 / 框选。
/// AE2-2/3/4：顶点、三角面、变形器手柄、遮罩的编辑手势都走 `doc.command`。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_scene_provider.dart';
import '../../core/engine/am_types.dart';
import '../../core/engine/local_eval.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/engine_providers.dart';
import '../../core/state/runtime_controller.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';
import 'canvas_painter.dart';

/// 画布组件。
class CanvasView extends ConsumerStatefulWidget {
  const CanvasView({super.key});

  @override
  ConsumerState<CanvasView> createState() => _CanvasViewState();
}

enum _DragMode { none, pan, vertex, handle, rotation, box }

class _CanvasViewState extends ConsumerState<CanvasView> {
  _DragMode _mode = _DragMode.none;
  Offset _lastPointer = Offset.zero;
  Offset _boxStart = Offset.zero;
  Rect? _boxRect;
  String? _hoverNode;
  int? _dragVertex;
  ({String id, int index, bool isRotation})? _dragHandle;
  double _dragStartAngle = 0;
  Size _canvasSize = Size.zero;
  Timer? _viewSync;
  int _lastFitToken = -1;

  @override
  void initState() {
    super.initState();
    // 视图变化回推引擎，保证命中测试与投影一致。
    ref.listenManual<ViewportState>(viewportProvider, (previous, next) {
      _syncView(next);
    });
  }

  @override
  void dispose() {
    _viewSync?.cancel();
    super.dispose();
  }

  void _syncView(ViewportState viewport) {
    _viewSync?.cancel();
    _viewSync = Timer(const Duration(milliseconds: 40), () {
      final engine = ref.read(engineProvider);
      engine
          .call('renderer.view', <String, Object?>{
            'pan': <Object?>[viewport.pan.dx, viewport.pan.dy],
            'zoom': viewport.zoom,
            'flip_x': viewport.flipX,
            'flip_y': viewport.flipY,
            'canvas': <Object?>[
              viewport.canvasSize.width,
              viewport.canvasSize.height,
            ],
          })
          .catchError((Object _) => const <String, Object?>{});
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    final viewport = ref.watch(viewportProvider);
    final selection = ref.watch(selectionProvider);
    final tool = ref.watch(toolProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final texture = ref.watch(engineTextureProvider);
    final sceneProvider = ref.watch(sceneProviderProvider);
    final runtime = ref.watch(runtimeProvider);
    ref.watch(revisionProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_canvasSize != size) {
          _canvasSize = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(viewportProvider.notifier).setCanvasSize(size);
            final engine = ref.read(engineProvider);
            engine
                .call('renderer.resize', <String, Object?>{
                  'width': size.width,
                  'height': size.height,
                })
                .catchError((Object _) => const <String, Object?>{});
          });
        }

        final scene = sceneProvider?.buildScene(
          selectedVertices: selection.vertices,
          selectedNode: selection.primary,
        );

        // 适应窗口请求：拿到包围盒后执行一次。
        if (scene != null && viewport.fitRequested != _lastFitToken) {
          _lastFitToken = viewport.fitRequested;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(viewportProvider.notifier).fitTo(scene.bounds);
          });
        }

        final ghosts = _buildGhosts(sceneProvider, scene, settings);
        final background = sceneProvider == null
            ? tokens.canvasBackground
            : _backgroundOf(sceneProvider.background, tokens.canvasBackground);

        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: _buildSurface(
                context,
                scene: scene,
                texture: texture,
                viewport: viewport,
                background: background,
                ghosts: ghosts,
                settings: settings,
                selection: selection,
                tool: tool,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: CanvasToolbar(
                viewport: viewport,
                scene: scene,
                runtime: runtime,
              ),
            ),
            if (_boxRect != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BoxSelectPainter(
                      rect: _boxRect!,
                      color: tokens.selectionStroke,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _backgroundOf(List<double> rgba, Color fallback) {
    if (rgba.length < 4 || rgba[3] <= 0) return fallback;
    int channel(double value) => (value.clamp(0.0, 1.0) * 255).round();
    return Color.fromARGB(
      channel(rgba[3]),
      channel(rgba[0]),
      channel(rgba[1]),
      channel(rgba[2]),
    );
  }

  List<OnionGhost> _buildGhosts(
    AmSceneProvider? provider,
    AmScene? scene,
    AppSettings settings,
  ) {
    if (provider == null || scene == null || !settings.onionSkin) {
      return const <OnionGhost>[];
    }
    final runtime = ref.read(runtimeProvider);
    final document = ref.read(documentProvider);
    final motion = document.motions
        .map(asJsonMap)
        .where((m) => '${m['name']}' == runtime.motion)
        .firstOrNull;
    if (motion == null) return const <OnionGhost>[];
    final frame = 1 / 24;
    final ghosts = <OnionGhost>[];
    final tokens = AppTheme.of(context);
    for (var i = 1; i <= settings.onionSkinFrames; i++) {
      for (final direction in <int>[-1, 1]) {
        final time = runtime.time + direction * frame * i;
        if (time < 0) continue;
        final params = <String, double>{...runtime.params};
        for (final curve in asJsonList(motion['curves'])) {
          final item = asJsonMap(curve);
          final param = '${item['param']}';
          if (param.isEmpty) continue;
          params[param] = evaluateCurve(
            asJsonList(item['keys']).map(asJsonMap).toList(),
            time,
          );
        }
        ghosts.add(
          OnionGhost(
            scene: provider.buildSceneWith(params: params),
            opacity: 0.35 / i,
            color: direction < 0 ? tokens.warning : tokens.accentSecondary,
          ),
        );
      }
    }
    return ghosts;
  }

  Widget _buildSurface(
    BuildContext context, {
    required AmScene? scene,
    required AmTextureInfo? texture,
    required ViewportState viewport,
    required Color background,
    required List<OnionGhost> ghosts,
    required AppSettings settings,
    required SelectionState selection,
    required EditorTool tool,
  }) {
    final tokens = AppTheme.of(context);

    Widget content;
    final textureId = texture != null && texture.isBridged
        ? texture.textureId
        : 0;
    if (textureId > 0) {
      // 引擎纹理：视图变换交给 Flutter，交互仍走引擎坐标接口。
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(
            viewport.pan.dx * viewport.zoom,
            -viewport.pan.dy * viewport.zoom,
            0,
            1,
          )
          ..scaleByDouble(
            viewport.zoom * (viewport.flipX ? -1 : 1),
            viewport.zoom * (viewport.flipY ? -1 : 1),
            1,
            1,
          ),
        child: Texture(textureId: textureId),
      );
    } else if (scene != null) {
      content = CustomPaint(
        painter: CanvasScenePainter(
          scene: scene,
          viewport: viewport,
          tokens: tokens,
          options: CanvasPaintOptions(
            showGrid: settings.showGrid,
            showGuides: settings.showGuides,
            showWireframe: true,
            showVertices: tool.isMeshEdit || selection.vertices.isNotEmpty,
            showHandles: true,
            showBounds: false,
            background: background,
            selectedVertices: selection.vertices,
            selectedNode: selection.primary,
            hoverNode: _hoverNode,
            ghosts: ghosts,
          ),
        ),
      );
    } else {
      content = Center(
        child: Text(
          'canvas.noEngine'.tr(),
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
      );
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
          ref
              .read(viewportProvider.notifier)
              .zoomAt(event.localPosition, factor);
        }
      },
      onPointerDown: (event) {
        if (event.buttons == kMiddleMouseButton) {
          _mode = _DragMode.pan;
          _lastPointer = event.localPosition;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _handleTap(details.localPosition),
        onSecondaryTapUp: (details) => _handleContextMenu(details),
        onPanStart: (details) => _handlePanStart(details.localPosition),
        onPanUpdate: (details) => _handlePanUpdate(details.localPosition),
        onPanEnd: (_) => _handlePanEnd(),
        onDoubleTapDown: (details) => _handleDoubleTap(details.localPosition),
        child: MouseRegion(
          onHover: (event) => _handleHover(event.localPosition),
          child: Container(color: background, child: content),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 交互
  // ---------------------------------------------------------------------------

  AmScene? _scene() {
    final provider = ref.read(sceneProviderProvider);
    if (provider == null) return null;
    final selection = ref.read(selectionProvider);
    return provider.buildScene(
      selectedVertices: selection.vertices,
      selectedNode: selection.primary,
    );
  }

  void _handleHover(Offset position) {
    final scene = _scene();
    if (scene == null) return;
    final viewport = ref.read(viewportProvider);
    final world = viewport.screenToWorld(position);
    final hit = hitTestScene(scene, world);
    if (hit != _hoverNode) {
      setState(() => _hoverNode = hit);
    }
  }

  void _handleTap(Offset position) {
    final scene = _scene();
    if (scene == null) return;
    final viewport = ref.read(viewportProvider);
    final world = viewport.screenToWorld(position);
    final selection = ref.read(selectionProvider);
    final tool = ref.read(toolProvider);

    // 1. 先看变形器手柄。
    final handle = nearestDeformerHandle(scene, position, viewport);
    if (handle != null) {
      ref.read(selectionProvider.notifier).select(handle.id);
      ref.read(toolProvider.notifier).setTool(EditorTool.deformer);
      return;
    }

    // 2. 网格编辑：先看顶点。
    if (tool.isMeshEdit && selection.primary != null) {
      final drawable = scene.drawables
          .where((d) => d.id == selection.primary)
          .firstOrNull;
      if (drawable != null) {
        final vertex = nearestVertex(drawable, position, viewport);
        if (vertex != null) {
          final additive = HardwareKeyboard.instance.isShiftPressed;
          if (additive) {
            ref.read(selectionProvider.notifier).toggleVertex(vertex);
          } else {
            ref.read(selectionProvider.notifier).setVertices(<int>[vertex]);
          }
          return;
        }
      }
    }

    // 3. 节点命中测试（走引擎接口，保证与渲染一致）。
    _pickAt(position, world);
  }

  Future<void> _pickAt(Offset position, Offset world) async {
    final engine = ref.read(engineProvider);
    String? hit;
    try {
      final result = await engine.call('renderer.pick', <String, Object?>{
        'x': position.dx,
        'y': position.dy,
        'space': 'screen',
      });
      hit = result['id'] as String?;
    } on AmException {
      final scene = _scene();
      hit = scene == null ? null : hitTestScene(scene, world);
    }
    if (!mounted) return;
    if (hit == null) {
      if (!HardwareKeyboard.instance.isShiftPressed) {
        ref.read(selectionProvider.notifier).clear();
      }
      return;
    }
    ref
        .read(selectionProvider.notifier)
        .select(hit, additive: HardwareKeyboard.instance.isShiftPressed);
  }

  void _handleDoubleTap(Offset position) {
    final scene = _scene();
    if (scene == null) return;
    final viewport = ref.read(viewportProvider);
    final selection = ref.read(selectionProvider);
    final drawable = scene.drawables
        .where((d) => d.id == selection.primary)
        .firstOrNull;
    if (drawable == null) return;
    final vertex = nearestVertex(drawable, position, viewport);
    if (vertex == null) return;
    ref.read(toolProvider.notifier).setTool(EditorTool.vertex);
    ref.read(selectionProvider.notifier).setVertices(<int>[vertex]);
  }

  void _handlePanStart(Offset position) {
    final scene = _scene();
    final selection = ref.read(selectionProvider);
    final tool = ref.read(toolProvider);
    _lastPointer = position;
    _dragVertex = null;
    _dragHandle = null;

    if (_spacePressed() || HardwareKeyboard.instance.isControlPressed) {
      _mode = _DragMode.pan;
      return;
    }
    if (scene == null) {
      _mode = _DragMode.pan;
      return;
    }

    final viewport = ref.read(viewportProvider);
    if (tool == EditorTool.deformer || selection.primary != null) {
      final handle = nearestDeformerHandle(scene, position, viewport);
      if (handle != null) {
        _dragHandle = handle;
        _mode = handle.isRotation ? _DragMode.rotation : _DragMode.handle;
        final deformer = scene.deformers
            .where((d) => d.id == handle.id)
            .firstOrNull;
        _dragStartAngle = deformer?.angle ?? 0;
        return;
      }
    }

    if (tool.isMeshEdit && selection.primary != null) {
      final drawable = scene.drawables
          .where((d) => d.id == selection.primary)
          .firstOrNull;
      if (drawable != null) {
        final vertex = nearestVertex(drawable, position, viewport);
        if (vertex != null) {
          _dragVertex = vertex;
          _mode = _DragMode.vertex;
          if (!selection.vertices.contains(vertex)) {
            ref.read(selectionProvider.notifier).setVertices(<int>[vertex]);
          }
          return;
        }
      }
    }

    _mode = _DragMode.box;
    _boxStart = position;
    setState(() => _boxRect = Rect.fromPoints(position, position));
  }

  void _handlePanUpdate(Offset position) {
    switch (_mode) {
      case _DragMode.none:
        return;
      case _DragMode.pan:
        final delta = position - _lastPointer;
        _lastPointer = position;
        ref
            .read(viewportProvider.notifier)
            .panBy(Offset(delta.dx / _zoom(), -delta.dy / _zoom()));
      case _DragMode.vertex:
        _dragSelectedVertices(position);
      case _DragMode.handle:
        _dragControlPoint(position);
      case _DragMode.rotation:
        _dragRotation(position);
      case _DragMode.box:
        setState(() => _boxRect = Rect.fromPoints(_boxStart, position));
    }
  }

  bool _spacePressed() => HardwareKeyboard.instance.logicalKeysPressed.contains(
    LogicalKeyboardKey.space,
  );

  double _zoom() => ref.read(viewportProvider).zoom;

  void _dragSelectedVertices(Offset position) {
    final delta = position - _lastPointer;
    _lastPointer = position;
    final selection = ref.read(selectionProvider);
    final target = selection.primary;
    if (target == null) return;
    var indices = selection.vertices;
    if (indices.isEmpty && _dragVertex != null) indices = <int>[_dragVertex!];
    if (indices.isEmpty) return;
    final world = Offset(delta.dx / _zoom(), -delta.dy / _zoom());
    ref.read(documentProvider.notifier).dispatch(
      'mesh.move_vertices',
      <String, Object?>{
        'id': target,
        'indices': indices,
        'dx': world.dx,
        'dy': world.dy,
      },
    );
  }

  void _dragControlPoint(Offset position) {
    final handle = _dragHandle;
    if (handle == null) return;
    final delta = position - _lastPointer;
    _lastPointer = position;
    ref
        .read(documentProvider.notifier)
        .dispatch('deformer.move_control_point', <String, Object?>{
          'id': handle.id,
          'index': handle.index,
          'dx': delta.dx / _zoom(),
          'dy': -delta.dy / _zoom(),
        });
  }

  void _dragRotation(Offset position) {
    final handle = _dragHandle;
    if (handle == null) return;
    final scene = _scene();
    if (scene == null) return;
    final deformer = scene.deformers
        .where((d) => d.id == handle.id)
        .firstOrNull;
    if (deformer == null) return;
    final viewport = ref.read(viewportProvider);
    final pivot = viewport.worldToScreen(deformer.pivot);
    final current = math.atan2(
      -(position.dy - pivot.dy),
      position.dx - pivot.dx,
    );
    final start = math.atan2(
      -(_lastPointer.dy - pivot.dy),
      _lastPointer.dx - pivot.dx,
    );
    _lastPointer = position;
    final next = _dragStartAngle + (current - start);
    _dragStartAngle = next;
    ref.read(documentProvider.notifier).dispatch(
      'node.set_property',
      <String, Object?>{'id': handle.id, 'key': 'angle', 'value': next},
    );
  }

  void _handlePanEnd() {
    if (_mode == _DragMode.box && _boxRect != null) {
      _applyBoxSelection(_boxRect!);
    }
    _mode = _DragMode.none;
    _dragVertex = null;
    _dragHandle = null;
    if (_boxRect != null) setState(() => _boxRect = null);
  }

  void _applyBoxSelection(Rect rect) {
    final scene = _scene();
    if (scene == null) return;
    final viewport = ref.read(viewportProvider);
    final selection = ref.read(selectionProvider);
    final drawable = scene.drawables
        .where((d) => d.id == selection.primary)
        .firstOrNull;
    if (drawable == null) {
      // 没有网格目标时按节点框选。
      final ids = <String>[];
      for (final item in scene.drawables) {
        final inside = item.vertices.any(
          (v) => rect.contains(viewport.worldToScreen(v)),
        );
        if (inside) ids.add(item.id);
      }
      if (ids.isNotEmpty) {
        ref.read(selectionProvider.notifier).selectMany(ids);
      }
      return;
    }
    final indices = <int>[];
    for (var i = 0; i < drawable.vertices.length; i++) {
      if (rect.contains(viewport.worldToScreen(drawable.vertices[i]))) {
        indices.add(i);
      }
    }
    if (indices.isEmpty) {
      ref.read(selectionProvider.notifier).setVertices(const <int>[]);
      return;
    }
    ref
        .read(selectionProvider.notifier)
        .setVertices(
          indices,
          additive: HardwareKeyboard.instance.isShiftPressed,
        );
    ref.read(toolProvider.notifier).setTool(EditorTool.vertex);
  }

  Future<void> _handleContextMenu(TapUpDetails details) async {
    final position = details.localPosition;
    final scene = _scene();
    if (scene == null) return;
    final viewport = ref.read(viewportProvider);
    final world = viewport.screenToWorld(position);
    final hit = hitTestScene(scene, world);
    if (hit != null) {
      ref.read(selectionProvider.notifier).select(hit);
    }
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = ref.read(selectionProvider).primary;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          1,
          1,
        ),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'fit',
          child: Text('canvas.menu.fit'.tr()),
        ),
        PopupMenuItem<String>(
          value: 'resetView',
          child: Text('canvas.menu.resetView'.tr()),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'toggleVisible',
          enabled: selected != null,
          child: Text('canvas.menu.toggleVisible'.tr()),
        ),
        PopupMenuItem<String>(
          value: 'rename',
          enabled: selected != null,
          child: Text('canvas.menu.rename'.tr()),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: selected != null,
          child: Text('canvas.menu.delete'.tr()),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    final document = ref.read(documentProvider.notifier);
    switch (choice) {
      case 'fit':
        ref.read(viewportProvider.notifier).fitTo(scene.bounds);
      case 'resetView':
        ref.read(viewportProvider.notifier).reset();
      case 'toggleVisible':
        if (selected != null) {
          final node = ref.read(documentProvider).nodes[selected];
          await document.dispatch('node.set_visible', <String, Object?>{
            'id': selected,
            'value': !(asBool(node?['visible'], true)),
          });
        }
      case 'rename':
        if (selected != null) {
          final node = ref.read(documentProvider).nodes[selected];
          final name = await _askName('${node?['name'] ?? ''}');
          if (name != null && name.isNotEmpty) {
            await document.dispatch('node.rename', <String, Object?>{
              'id': selected,
              'name': name,
            });
          }
        }
      case 'delete':
        if (selected != null) {
          await document.dispatch('node.delete', <String, Object?>{
            'id': selected,
          });
          ref.read(selectionProvider.notifier).clear();
        }
    }
  }

  Future<String?> _askName(String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('canvas.menu.rename'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'common.name'.tr()),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text('common.confirm'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

class _BoxSelectPainter extends CustomPainter {
  const _BoxSelectPainter({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BoxSelectPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

/// 画布顶部工具条：视图操作 + 播放控制。
class CanvasToolbar extends ConsumerWidget {
  const CanvasToolbar({
    super.key,
    required this.viewport,
    required this.scene,
    required this.runtime,
  });

  final ViewportState viewport;
  final AmScene? scene;
  final RuntimeState runtime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final viewportController = ref.read(viewportProvider.notifier);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: tokens.panelHeader.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: tokens.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SmallIconButton(
                icon: Icons.fit_screen,
                tooltipKey: 'canvas.fit',
                onPressed: () => viewportController.fitTo(
                  scene?.bounds ?? const <double>[-100, -100, 100, 100],
                ),
              ),
              SmallIconButton(
                icon: Icons.restart_alt,
                tooltipKey: 'canvas.resetView',
                onPressed: viewportController.reset,
              ),
              SmallIconButton(
                icon: Icons.flip,
                tooltipKey: 'canvas.flipX',
                selected: viewport.flipX,
                onPressed: viewportController.toggleFlipX,
              ),
              SmallIconButton(
                icon: Icons.flip_camera_android,
                tooltipKey: 'canvas.flipY',
                selected: viewport.flipY,
                onPressed: viewportController.toggleFlipY,
              ),
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: tokens.divider,
              ),
              SmallIconButton(
                icon: Icons.grid_4x4,
                tooltipKey: 'canvas.toggleGrid',
                selected: settings.showGrid,
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .patch((s) => s.copyWith(showGrid: !s.showGrid)),
              ),
              SmallIconButton(
                icon: Icons.align_horizontal_center,
                tooltipKey: 'canvas.toggleGuides',
                selected: settings.showGuides,
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .patch((s) => s.copyWith(showGuides: !s.showGuides)),
              ),
              SmallIconButton(
                icon: Icons.layers,
                tooltipKey: 'canvas.toggleOnion',
                selected: settings.onionSkin,
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .patch((s) => s.copyWith(onionSkin: !s.onionSkin)),
              ),
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: tokens.divider,
              ),
              SmallIconButton(
                icon: runtime.playing ? Icons.pause : Icons.play_arrow,
                tooltipKey: runtime.playing ? 'motion.pause' : 'motion.play',
                onPressed: () {
                  final runtimeController = ref.read(runtimeProvider.notifier);
                  if (runtime.playing) {
                    runtimeController.pause();
                  } else if (runtime.motion != null) {
                    runtimeController.play(runtime.motion!);
                  }
                },
              ),
              SmallIconButton(
                icon: Icons.stop,
                tooltipKey: 'motion.stop',
                onPressed: () => ref.read(runtimeProvider.notifier).pause(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${viewport.zoom.toStringAsFixed(2)}x',
                  style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
