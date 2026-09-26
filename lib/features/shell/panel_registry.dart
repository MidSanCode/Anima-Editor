/// 面板注册表：面板声明（默认位置、图标、标题）与内容构造器（AE0-2）。
library;

import 'package:flutter/material.dart';

import '../../core/layout/dock_layout.dart';
import '../canvas/canvas_view.dart';
import '../panels/curve_panel.dart';
import '../panels/effect_panels.dart';
import '../panels/hierarchy_panel.dart';
import '../panels/inspector_panel.dart';
import '../panels/keyform_panel.dart';
import '../panels/meta_panels.dart';
import '../panels/modeler_panels.dart';
import '../panels/parameter_panel.dart';
import '../panels/timeline_panel.dart';

/// 面板 id 常量（避免字符串散落各处）。
class PanelIds {
  const PanelIds._();

  static const String canvas = 'canvas';
  static const String hierarchy = 'hierarchy';
  static const String parameters = 'parameters';
  static const String inspector = 'inspector';
  static const String mesh = 'mesh';
  static const String deformer = 'deformer';
  static const String keyform = 'keyform';
  static const String timeline = 'timeline';
  static const String curve = 'curve';
  static const String physics = 'physics';
  static const String expressions = 'expressions';
  static const String pose = 'pose';
  static const String lipsync = 'lipsync';
  static const String modelSettings = 'model_settings';
  static const String validation = 'validation';
  static const String history = 'history';
  static const String performance = 'performance';
}

/// 面板声明。
const List<DockPanelSpec> kEditorPanelSpecs = <DockPanelSpec>[
  DockPanelSpec(
    id: PanelIds.canvas,
    titleKey: 'panel.canvas',
    icon: Icons.crop_original,
    defaultSlot: DockSlot.center,
    closable: false,
  ),
  DockPanelSpec(
    id: PanelIds.hierarchy,
    titleKey: 'panel.hierarchy',
    icon: Icons.account_tree,
    defaultSlot: DockSlot.left,
  ),
  DockPanelSpec(
    id: PanelIds.parameters,
    titleKey: 'panel.parameter',
    icon: Icons.tune,
    defaultSlot: DockSlot.left,
  ),
  DockPanelSpec(
    id: PanelIds.mesh,
    titleKey: 'panel.mesh',
    icon: Icons.grid_on,
    defaultSlot: DockSlot.left,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.deformer,
    titleKey: 'panel.deformer',
    icon: Icons.architecture,
    defaultSlot: DockSlot.left,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.keyform,
    titleKey: 'panel.keyform',
    icon: Icons.bookmark,
    defaultSlot: DockSlot.left,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.inspector,
    titleKey: 'panel.inspector',
    icon: Icons.article,
    defaultSlot: DockSlot.right,
  ),
  DockPanelSpec(
    id: PanelIds.physics,
    titleKey: 'panel.physics',
    icon: Icons.waves,
    defaultSlot: DockSlot.right,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.expressions,
    titleKey: 'panel.expression',
    icon: Icons.emoji_emotions,
    defaultSlot: DockSlot.right,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.pose,
    titleKey: 'panel.pose',
    icon: Icons.accessibility_new,
    defaultSlot: DockSlot.right,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.lipsync,
    titleKey: 'panel.lipsync',
    icon: Icons.record_voice_over,
    defaultSlot: DockSlot.right,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.modelSettings,
    titleKey: 'panel.model',
    icon: Icons.settings_suggest,
    defaultSlot: DockSlot.right,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.validation,
    titleKey: 'panel.validation',
    icon: Icons.rule,
    defaultSlot: DockSlot.right,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.history,
    titleKey: 'panel.history',
    icon: Icons.history,
    defaultSlot: DockSlot.right,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.performance,
    titleKey: 'panel.performance',
    icon: Icons.speed,
    defaultSlot: DockSlot.right,
    hiddenByDefault: true,
  ),
  DockPanelSpec(
    id: PanelIds.timeline,
    titleKey: 'panel.timeline',
    icon: Icons.timeline,
    defaultSlot: DockSlot.bottom,
  ),
  DockPanelSpec(
    id: PanelIds.curve,
    titleKey: 'panel.curve',
    icon: Icons.show_chart,
    defaultSlot: DockSlot.bottom,
    hiddenByDefault: true,
  ),
];

/// 面板内容构造器。
///
/// 标题栏由 [DockHost] 统一渲染（标签页 + 拖拽把手），面板自身只负责内容。
Map<String, WidgetBuilder> buildPanelBuilders() => <String, WidgetBuilder>{
  PanelIds.canvas: (_) => const CanvasView(),
  PanelIds.hierarchy: (_) => const HierarchyPanel(),
  PanelIds.parameters: (_) => const ParameterPanel(),
  PanelIds.inspector: (_) => const InspectorPanel(),
  PanelIds.mesh: (_) => const MeshPanel(),
  PanelIds.deformer: (_) => const DeformerPanel(),
  PanelIds.keyform: (_) => const KeyformPanel(),
  PanelIds.timeline: (_) => const TimelinePanel(),
  PanelIds.curve: (_) => const CurvePanel(),
  PanelIds.physics: (_) => const PhysicsPanel(),
  PanelIds.expressions: (_) => const ExpressionPanel(),
  PanelIds.pose: (_) => const PosePanel(),
  PanelIds.lipsync: (_) => const LipsyncPanel(),
  PanelIds.modelSettings: (_) => const ModelSettingsPanel(),
  PanelIds.validation: (_) => const ValidationPanel(),
  PanelIds.history: (_) => const HistoryPanel(),
  PanelIds.performance: (_) => const PerformancePanel(),
};
