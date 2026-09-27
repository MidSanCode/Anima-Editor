/// 网格编辑（AE2-2）与变形器编辑（AE2-3）。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_types.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

/// 网格面板。
class MeshPanel extends ConsumerStatefulWidget {
  const MeshPanel({super.key});

  @override
  ConsumerState<MeshPanel> createState() => _MeshPanelState();
}

class _MeshPanelState extends ConsumerState<MeshPanel> {
  int _rows = 4;
  int _cols = 4;
  double _splitT = 0.5;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    final selection = ref.watch(selectionProvider);
    final id = selection.primary;
    if (id == null) {
      return EmptyState(
        icon: Icons.grid_on,
        titleKey: 'panel.mesh.empty',
        subtitleKey: 'panel.mesh.emptyHint',
      );
    }
    final mesh = ref.watch(meshProvider(id)).value ?? const <String, Object?>{};
    final vertices = asJsonList(mesh['vertices']);
    final indices = asJsonList(mesh['indices']);
    final selected = selection.vertices;

    return Column(
      children: <Widget>[
        Expanded(
          child: PanelScroll(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SectionHeader(titleKey: 'panel.mesh.section.summary'),
                KeyValueRow(
                  labelKey: 'panel.mesh.vertexCount',
                  value: '${vertices.length}',
                ),
                KeyValueRow(
                  labelKey: 'panel.mesh.triangleCount',
                  value: '${indices.length ~/ 3}',
                ),
                KeyValueRow(
                  labelKey: 'panel.mesh.selectedCount',
                  value: '${selected.length}',
                ),
                SectionHeader(titleKey: 'panel.mesh.section.generate'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _IntField(
                          labelKey: 'panel.mesh.rows',
                          value: _rows,
                          onChanged: (value) => setState(() => _rows = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _IntField(
                          labelKey: 'panel.mesh.cols',
                          value: _cols,
                          onChanged: (value) => setState(() => _cols = value),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: <Widget>[
                      SmallTextButton(
                        labelKey: 'panel.mesh.autoGenerate',
                        icon: Icons.auto_fix_high,
                        onPressed: () => ref
                            .read(documentProvider.notifier)
                            .dispatch('mesh.auto_generate', <String, Object?>{
                              'id': id,
                              'rows': _rows,
                              'cols': _cols,
                            }),
                      ),
                      const Spacer(),
                      SmallTextButton(
                        labelKey: 'panel.mesh.reset',
                        icon: Icons.restart_alt,
                        onPressed: () =>
                            ref.read(documentProvider.notifier).dispatch(
                              'mesh.auto_generate',
                              <String, Object?>{'id': id, 'rows': 1, 'cols': 1},
                            ),
                      ),
                    ],
                  ),
                ),
                SectionHeader(titleKey: 'panel.mesh.section.split'),
                LabeledSlider(
                  label: 'panel.mesh.splitT'.tr(),
                  value: _splitT,
                  min: 0.05,
                  max: 0.95,
                  defaultValue: 0.5,
                  onChanged: (value) => setState(() => _splitT = value),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SmallTextButton(
                    labelKey: 'panel.mesh.splitTriangle',
                    icon: Icons.call_split,
                    onPressed: selection.triangles.isEmpty
                        ? null
                        : () => ref.read(documentProvider.notifier).dispatch(
                            'mesh.split_triangle',
                            <String, Object?>{
                              'id': id,
                              'triangle': selection.triangles.first,
                              't': _splitT,
                            },
                          ),
                  ),
                ),
                SectionHeader(titleKey: 'panel.mesh.section.vertices'),
                if (selected.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      'panel.mesh.noVertexSelected'.tr(),
                      style: TextStyle(fontSize: 11, color: tokens.textMuted),
                    ),
                  )
                else
                  for (final index in selected.take(24))
                    _VertexRow(
                      index: index,
                      vertex: index < vertices.length
                          ? asJsonList(vertices[index])
                          : const <Object?>[],
                      onMove: (dx, dy) => ref
                          .read(documentProvider.notifier)
                          .dispatch('mesh.move_vertices', <String, Object?>{
                            'id': id,
                            'indices': <int>[index],
                            'dx': dx,
                            'dy': dy,
                          }),
                    ),
              ],
            ),
          ),
        ),
        _footer(id, selection),
      ],
    );
  }

  Widget _footer(String id, SelectionState selection) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.of(context).divider)),
      ),
      child: Row(
        children: <Widget>[
          SmallIconButton(
            icon: Icons.add,
            tooltipKey: 'panel.mesh.addVertex',
            onPressed: () => ref.read(documentProvider.notifier).dispatch(
              'mesh.add_vertices',
              <String, Object?>{
                'id': id,
                'vertices': <Object?>[
                  <Object?>[0.0, 0.0],
                ],
              },
            ),
          ),
          SmallIconButton(
            icon: Icons.remove,
            tooltipKey: 'panel.mesh.removeVertex',
            onPressed: selection.vertices.isEmpty
                ? null
                : () => ref.read(documentProvider.notifier).dispatch(
                    'mesh.remove_vertices',
                    <String, Object?>{'id': id, 'indices': selection.vertices},
                  ),
          ),
          const Spacer(),
          SmallIconButton(
            icon: Icons.select_all,
            tooltipKey: 'panel.mesh.selectAll',
            onPressed: () async {
              final mesh =
                  ref.read(meshProvider(id)).value ?? const <String, Object?>{};
              final count = asJsonList(mesh['vertices']).length;
              ref.read(selectionProvider.notifier).setVertices(<int>[
                for (var i = 0; i < count; i++) i,
              ]);
            },
          ),
          SmallIconButton(
            icon: Icons.deselect,
            tooltipKey: 'panel.mesh.clearSelection',
            onPressed: () =>
                ref.read(selectionProvider.notifier).setVertices(const <int>[]),
          ),
        ],
      ),
    );
  }
}

class _VertexRow extends StatelessWidget {
  const _VertexRow({
    required this.index,
    required this.vertex,
    required this.onMove,
  });

  final int index;
  final List<Object?> vertex;
  final void Function(double dx, double dy) onMove;

  @override
  Widget build(BuildContext context) {
    final x = asDouble(vertex.isNotEmpty ? vertex[0] : 0);
    final y = asDouble(vertex.length > 1 ? vertex[1] : 0);
    final tokens = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            child: Text(
              '#$index',
              style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              '${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          SmallIconButton(
            icon: Icons.arrow_left,
            tooltipKey: 'panel.mesh.nudgeLeft',
            onPressed: () => onMove(-1, 0),
          ),
          SmallIconButton(
            icon: Icons.arrow_right,
            tooltipKey: 'panel.mesh.nudgeRight',
            onPressed: () => onMove(1, 0),
          ),
          SmallIconButton(
            icon: Icons.arrow_upward,
            tooltipKey: 'panel.mesh.nudgeUp',
            onPressed: () => onMove(0, 1),
          ),
          SmallIconButton(
            icon: Icons.arrow_downward,
            tooltipKey: 'panel.mesh.nudgeDown',
            onPressed: () => onMove(0, -1),
          ),
        ],
      ),
    );
  }
}

/// 变形器面板。
class DeformerPanel extends ConsumerWidget {
  const DeformerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final selection = ref.watch(selectionProvider);
    final deformers = document.nodes.entries
        .where((entry) => AmNodeKind.parse(entry.value['type']).isDeformer)
        .toList();
    final id = selection.primary;
    final current = id != null ? document.nodes[id] : null;
    final kind = AmNodeKind.parse(current?['type']);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              SectionHeader(
                titleKey: 'panel.deformer.section.list',
                actions: <Widget>[
                  SmallIconButton(
                    icon: Icons.grid_on,
                    tooltipKey: 'panel.deformer.createWarp',
                    onPressed: () => ref
                        .read(documentProvider.notifier)
                        .dispatch('deformer.create_warp', <String, Object?>{
                          'name': 'Warp${deformers.length + 1}',
                          'rows': 2,
                          'cols': 2,
                        }),
                  ),
                  SmallIconButton(
                    icon: Icons.rotate_right,
                    tooltipKey: 'panel.deformer.createRotation',
                    onPressed: () => ref
                        .read(documentProvider.notifier)
                        .dispatch('deformer.create_rotation', <String, Object?>{
                          'name': 'Rotation${deformers.length + 1}',
                        }),
                  ),
                ],
              ),
              if (deformers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'panel.deformer.empty'.tr(),
                    style: TextStyle(fontSize: 11, color: tokens.textMuted),
                  ),
                )
              else
                for (final entry in deformers)
                  ListRow(
                    selected: selection.nodes.contains(entry.key),
                    onTap: () =>
                        ref.read(selectionProvider.notifier).select(entry.key),
                    leading: Icon(
                      AmNodeKind.parse(entry.value['type']) ==
                              AmNodeKind.warpDeformer
                          ? Icons.grid_on
                          : Icons.rotate_right,
                      size: 13,
                    ),
                    child: Text(
                      '${entry.value['name'] ?? entry.key}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
              if (kind.isDeformer) ...<Widget>[
                SectionHeader(titleKey: 'panel.deformer.section.detail'),
                if (kind == AmNodeKind.warpDeformer) ...<Widget>[
                  KeyValueRow(
                    labelKey: 'panel.inspector.rows',
                    value: '${asInt(current?['rows'])}',
                  ),
                  KeyValueRow(
                    labelKey: 'panel.inspector.cols',
                    value: '${asInt(current?['cols'])}',
                  ),
                ] else ...<Widget>[
                  LabeledSlider(
                    label: 'panel.deformer.angle'.tr(),
                    value: asDouble(current?['angle']),
                    min: -3.15,
                    max: 3.15,
                    defaultValue: 0,
                    onChanged: (value) => ref
                        .read(documentProvider.notifier)
                        .dispatch('node.set_property', <String, Object?>{
                          'id': id,
                          'key': 'angle',
                          'value': value,
                        }),
                  ),
                ],
                _ControlPointGrid(
                  nodeId: id!,
                  node: current ?? const <String, Object?>{},
                ),
                SectionHeader(titleKey: 'panel.deformer.section.bind'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'panel.deformer.bindHint'.tr(),
                    style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SmallTextButton(
                    labelKey: 'panel.deformer.bindSelected',
                    icon: Icons.link,
                    onPressed: selection.nodes.length < 2
                        ? null
                        : () async {
                            for (final nodeId in selection.nodes) {
                              if (nodeId == id) continue;
                              await ref
                                  .read(documentProvider.notifier)
                                  .dispatch(
                                    'deformer.set_parent',
                                    <String, Object?>{
                                      'id': nodeId,
                                      'parent': id,
                                    },
                                  );
                            }
                          },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlPointGrid extends ConsumerWidget {
  const _ControlPointGrid({required this.nodeId, required this.node});

  final String nodeId;
  final Map<String, Object?> node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final points = asJsonList(node['control_points']);
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'panel.deformer.noControlPoints'.tr(),
          style: TextStyle(fontSize: 11, color: tokens.textMuted),
        ),
      );
    }
    final selected = ref.watch(selectionProvider).vertices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          titleKey: 'panel.deformer.section.controlPoints',
          actions: <Widget>[
            SmallIconButton(
              icon: Icons.cleaning_services,
              tooltipKey: 'panel.deformer.resetControlPoints',
              onPressed: () => ref
                  .read(documentProvider.notifier)
                  .dispatch('node.set_property', <String, Object?>{
                    'id': nodeId,
                    'key': 'control_points',
                    'value': asJsonList(node['bounds']).isEmpty
                        ? points
                        : _resetPoints(node),
                  }),
            ),
          ],
        ),
        for (var i = 0; i < points.length && i < 64; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 30,
                  child: Text(
                    '#$i',
                    style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${asDouble(asJsonList(points[i]).isNotEmpty ? asJsonList(points[i])[0] : 0).toStringAsFixed(1)}, '
                    '${asDouble(asJsonList(points[i]).length > 1 ? asJsonList(points[i])[1] : 0).toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                SmallIconButton(
                  icon: Icons.my_location,
                  tooltipKey: 'panel.deformer.selectPoint',
                  selected: selected.contains(i),
                  onPressed: () => ref
                      .read(selectionProvider.notifier)
                      .setVertices(<int>[i]),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static List<Object?> _resetPoints(Map<String, Object?> node) {
    final rows = asInt(node['rows'], 2);
    final cols = asInt(node['cols'], 2);
    final bounds = asJsonList(node['bounds']);
    final x = bounds.isNotEmpty ? asDouble(bounds[0]) : -100.0;
    final y = bounds.length > 1 ? asDouble(bounds[1]) : -100.0;
    final w = bounds.length > 2 ? asDouble(bounds[2]) : 200.0;
    final h = bounds.length > 3 ? asDouble(bounds[3]) : 200.0;
    return <Object?>[
      for (var r = 0; r <= rows; r++)
        for (var c = 0; c <= cols; c++)
          <Object?>[x + w * c / cols, y + h * r / rows],
    ];
  }
}

class _IntField extends StatefulWidget {
  const _IntField({
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String labelKey;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    style: const TextStyle(fontSize: 11.5),
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      isDense: true,
      labelText: widget.labelKey.tr(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    ),
    onSubmitted: (value) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) widget.onChanged(parsed);
    },
  );
}
