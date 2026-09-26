/// UI 状态控制器：通知、选择、视图、工具、播放。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// 通知（错误横幅 / 轻提示 / 进度）
// ---------------------------------------------------------------------------

/// 通知级别。
enum NoticeLevel { info, success, warning, error }

/// 一条通知。
class Notice {
  const Notice({
    required this.level,
    required this.messageKey,
    this.args = const <String, String>{},
    this.detail,
    this.action,
    this.id,
  });

  final NoticeLevel level;

  /// i18n key（UI 文案不得硬编码）。
  final String messageKey;

  /// 插值参数。
  final Map<String, String> args;

  /// 技术细节（可展开；不进 i18n）。
  final String? detail;

  /// 可选的动作按钮（i18n key + 回调标签 id）。
  final String? action;

  final String? id;
}

/// 通知控制器。
class NotificationsController extends Notifier<List<Notice>> {
  int _sequence = 0;

  @override
  List<Notice> build() => const <Notice>[];

  String push(
    NoticeLevel level,
    String messageKey, {
    Map<String, String> args = const <String, String>{},
    String? detail,
    String? action,
  }) {
    final id = 'notice-${_sequence++}';
    state = <Notice>[
      ...state,
      Notice(
        level: level,
        messageKey: messageKey,
        args: args,
        detail: detail,
        action: action,
        id: id,
      ),
    ];
    return id;
  }

  void info(
    String key, {
    Map<String, String> args = const <String, String>{},
  }) => push(NoticeLevel.info, key, args: args);

  void success(
    String key, {
    Map<String, String> args = const <String, String>{},
  }) => push(NoticeLevel.success, key, args: args);

  void warn(
    String key, {
    Map<String, String> args = const <String, String>{},
    String? detail,
  }) => push(NoticeLevel.warning, key, args: args, detail: detail);

  void error(
    String key, {
    Map<String, String> args = const <String, String>{},
    String? detail,
  }) => push(NoticeLevel.error, key, args: args, detail: detail);

  void dismiss(String id) {
    state = state.where((notice) => notice.id != id).toList();
  }

  void clear() => state = const <Notice>[];
}

final notificationsProvider =
    NotifierProvider<NotificationsController, List<Notice>>(
      NotificationsController.new,
    );

// ---------------------------------------------------------------------------
// 选择与工具
// ---------------------------------------------------------------------------

/// 画布工具。
enum EditorTool {
  select('select'),
  vertex('vertex'),
  deformer('deformer'),
  mask('mask'),
  texture('texture');

  const EditorTool(this.wire);

  final String wire;

  bool get isMeshEdit => this == EditorTool.vertex;
}

/// 选择状态。
class SelectionState {
  const SelectionState({
    this.nodes = const <String>{},
    this.primary,
    this.vertices = const <int>[],
    this.triangles = const <int>[],
    this.useBoxSelect = false,
  });

  final Set<String> nodes;
  final String? primary;

  /// 当前可绘制对象的选中顶点索引。
  final List<int> vertices;
  final List<int> triangles;
  final bool useBoxSelect;

  bool get isEmpty => nodes.isEmpty;

  bool contains(String id) => nodes.contains(id);

  /// 网格编辑是否可用（必须正好选中一个可绘制对象）。
  bool get hasSingleDrawableTarget => primary != null;

  SelectionState copyWith({
    Set<String>? nodes,
    String? primary,
    bool clearPrimary = false,
    List<int>? vertices,
    List<int>? triangles,
    bool? useBoxSelect,
  }) => SelectionState(
    nodes: nodes ?? this.nodes,
    primary: clearPrimary ? null : (primary ?? this.primary),
    vertices: vertices ?? this.vertices,
    triangles: triangles ?? this.triangles,
    useBoxSelect: useBoxSelect ?? this.useBoxSelect,
  );
}

/// 选择控制器。
class SelectionController extends Notifier<SelectionState> {
  @override
  SelectionState build() => const SelectionState();

  void select(String id, {bool additive = false}) {
    if (additive) {
      final nodes = <String>{...state.nodes};
      if (!nodes.add(id)) nodes.remove(id);
      state = state.copyWith(
        nodes: nodes,
        primary: nodes.contains(id)
            ? id
            : (nodes.isEmpty ? null : state.primary),
        clearPrimary: nodes.isEmpty,
        vertices: const <int>[],
      );
      return;
    }
    state = SelectionState(nodes: <String>{id}, primary: id);
  }

  void selectMany(Iterable<String> ids) {
    final nodes = ids.toSet();
    state = SelectionState(
      nodes: nodes,
      primary: nodes.isEmpty ? null : nodes.first,
    );
  }

  void clear() => state = const SelectionState();

  void setVertices(List<int> vertices, {bool additive = false}) {
    final next = additive
        ? <int>{...state.vertices, ...vertices}.toList()
        : vertices;
    state = state.copyWith(vertices: next..sort());
  }

  void toggleVertex(int index) {
    final next = <int>{...state.vertices};
    if (!next.add(index)) next.remove(index);
    state = state.copyWith(vertices: next.toList()..sort());
  }

  void setTriangles(List<int> triangles) =>
      state = state.copyWith(triangles: triangles);

  void setBoxSelect(bool enabled) =>
      state = state.copyWith(useBoxSelect: enabled);
}

final selectionProvider = NotifierProvider<SelectionController, SelectionState>(
  SelectionController.new,
);

/// 工具控制器。
class ToolController extends Notifier<EditorTool> {
  @override
  EditorTool build() => EditorTool.select;

  void setTool(EditorTool tool) => state = tool;
}

final toolProvider = NotifierProvider<ToolController, EditorTool>(
  ToolController.new,
);

// ---------------------------------------------------------------------------
// 画布视图
// ---------------------------------------------------------------------------

/// 视图状态：世界（画布像素，原点中心，Y 向上）↔ 屏幕。
class ViewportState {
  const ViewportState({
    this.pan = Offset.zero,
    this.zoom = 1.0,
    this.flipX = false,
    this.flipY = false,
    this.canvasSize = const Size(1280, 720),
    this.fitRequested = 0,
  });

  final Offset pan;
  final double zoom;
  final bool flipX;
  final bool flipY;
  final Size canvasSize;

  /// 每次“适应窗口”自增，画布据此重新计算。
  final int fitRequested;

  ViewportState copyWith({
    Offset? pan,
    double? zoom,
    bool? flipX,
    bool? flipY,
    Size? canvasSize,
    int? fitRequested,
  }) => ViewportState(
    pan: pan ?? this.pan,
    zoom: zoom ?? this.zoom,
    flipX: flipX ?? this.flipX,
    flipY: flipY ?? this.flipY,
    canvasSize: canvasSize ?? this.canvasSize,
    fitRequested: fitRequested ?? this.fitRequested,
  );

  Offset worldToScreen(Offset world) => Offset(
    canvasSize.width / 2 + (world.dx * (flipX ? -1 : 1) + pan.dx) * zoom,
    canvasSize.height / 2 - (world.dy * (flipY ? -1 : 1) + pan.dy) * zoom,
  );

  Offset screenToWorld(Offset screen) {
    final x = (screen.dx - canvasSize.width / 2) / zoom - pan.dx;
    final y = -(screen.dy - canvasSize.height / 2) / zoom - pan.dy;
    return Offset(flipX ? -x : x, flipY ? -y : y);
  }
}

/// 视图控制器。
class ViewportController extends Notifier<ViewportState> {
  @override
  ViewportState build() => const ViewportState();

  void setCanvasSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if (state.canvasSize == size) return;
    state = state.copyWith(canvasSize: size);
  }

  void panBy(Offset delta) => state = state.copyWith(pan: state.pan + delta);

  void setPan(Offset pan) => state = state.copyWith(pan: pan);

  void zoomAt(Offset focal, double factor) {
    final next = (state.zoom * factor).clamp(0.05, 32.0);
    if (next == state.zoom) return;
    final before = state.screenToWorld(focal);
    final updated = state.copyWith(zoom: next);
    final after = updated.screenToWorld(focal);
    state = updated.copyWith(pan: updated.pan + (after - before));
  }

  void setZoom(double zoom) =>
      state = state.copyWith(zoom: zoom.clamp(0.05, 32.0));

  void toggleFlipX() => state = state.copyWith(flipX: !state.flipX);

  void toggleFlipY() => state = state.copyWith(flipY: !state.flipY);

  void reset() => state = state.copyWith(
    pan: Offset.zero,
    zoom: 1,
    flipX: false,
    flipY: false,
  );

  /// 适应内容包围盒 `[left, top, right, bottom]`（世界坐标）。
  void fitTo(List<double> bounds, {double padding = 0.08}) {
    final width = bounds[2] - bounds[0];
    final height = bounds[3] - bounds[1];
    if (width <= 0 || height <= 0) {
      reset();
      return;
    }
    final available = Size(
      state.canvasSize.width * (1 - padding * 2),
      state.canvasSize.height * (1 - padding * 2),
    );
    final zoom = math.min(available.width / width, available.height / height);
    final center = Offset(
      (bounds[0] + bounds[2]) / 2,
      (bounds[1] + bounds[3]) / 2,
    );
    final clamped = zoom.clamp(0.05, 32.0);
    state = state.copyWith(
      zoom: clamped,
      pan: Offset(-center.dx, -center.dy),
      fitRequested: state.fitRequested + 1,
    );
  }

  /// 请求适应窗口（画布拿到下一帧的场景包围盒后执行）。
  void requestFit() =>
      state = state.copyWith(fitRequested: state.fitRequested + 1);

  /// 按轴翻转。
  void flipAxes({bool horizontal = true}) {
    if (horizontal) {
      toggleFlipX();
    } else {
      toggleFlipY();
    }
  }
}

final viewportProvider = NotifierProvider<ViewportController, ViewportState>(
  ViewportController.new,
);

// ---------------------------------------------------------------------------
// 播放
// ---------------------------------------------------------------------------

/// 播放状态。
class PlaybackState {
  const PlaybackState({
    this.playing = false,
    this.recording = false,
    this.time = 0,
    this.duration = 3,
    this.loop = true,
    this.speed = 1.0,
    this.motion,
    this.selectedKeys = const <String>{},
  });

  final bool playing;
  final bool recording;
  final double time;
  final double duration;
  final bool loop;
  final double speed;
  final String? motion;

  /// 曲线编辑器选中：`param|time`。
  final Set<String> selectedKeys;

  PlaybackState copyWith({
    bool? playing,
    bool? recording,
    double? time,
    double? duration,
    bool? loop,
    double? speed,
    String? motion,
    Set<String>? selectedKeys,
  }) => PlaybackState(
    playing: playing ?? this.playing,
    recording: recording ?? this.recording,
    time: time ?? this.time,
    duration: duration ?? this.duration,
    loop: loop ?? this.loop,
    speed: speed ?? this.speed,
    motion: motion ?? this.motion,
    selectedKeys: selectedKeys ?? this.selectedKeys,
  );
}

/// 播放控制器。
class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  void play([String? motion]) =>
      state = state.copyWith(playing: true, motion: motion ?? state.motion);

  void pause() => state = state.copyWith(playing: false);

  void toggle() => state = state.copyWith(playing: !state.playing);

  void stop() => state = state.copyWith(playing: false, time: 0);

  void setTime(double time) =>
      state = state.copyWith(time: time.clamp(0, state.duration));

  void setDuration(double duration) =>
      state = state.copyWith(duration: math.max(0.1, duration));

  void setLoop(bool loop) => state = state.copyWith(loop: loop);

  void setSpeed(double speed) => state = state.copyWith(speed: speed);

  void selectMotion(String motion) => state = state.copyWith(motion: motion);

  void setRecording(bool recording) =>
      state = state.copyWith(recording: recording, playing: false);

  void toggleKeySelection(String key, {bool additive = false}) {
    final keys = <String>{...state.selectedKeys};
    if (additive) {
      if (!keys.add(key)) keys.remove(key);
    } else {
      keys
        ..clear()
        ..add(key);
    }
    state = state.copyWith(selectedKeys: keys);
  }

  void clearKeySelection() => state = state.copyWith(selectedKeys: <String>{});

  /// 推进播放头；返回新时间。
  double advance(double dt) {
    var next = state.time + dt * state.speed;
    if (next > state.duration) {
      if (state.loop) {
        next = state.duration <= 0 ? 0 : next % state.duration;
      } else {
        next = state.duration;
        state = state.copyWith(playing: false);
      }
    }
    state = state.copyWith(time: next);
    return next;
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);
