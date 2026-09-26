/// 属性面板：节点、变换、绘制、遮罩、网格/变形器摘要（AE1-3）。
library;

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_types.dart';
import '../../core/platform/file_service.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

/// 属性面板。
class InspectorPanel extends ConsumerWidget {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final selection = ref.watch(selectionProvider);
    final document = ref.watch(documentProvider);
    final id = selection.primary;

    if (id == null || !document.nodes.containsKey(id)) {
      return EmptyState(
        icon: Icons.tune,
        titleKey: 'panel.inspector.empty',
        subtitleKey: 'panel.inspector.emptyHint',
      );
    }

    final node = document.nodes[id] ?? const <String, Object?>{};
    final kind = AmNodeKind.parse(node['type'] ?? node['kind']);
    final detail = ref.watch(nodeDetailProvider(id));
    final mesh = detail.value == null ? null : asJsonMap(detail.value!['mesh']);

    return PanelScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(titleKey: 'panel.inspector.section.node'),
          KeyValueRow(labelKey: 'common.id', value: id, monospace: true),
          KeyValueRow(labelKey: 'common.kind', value: kind.wire),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 108,
                  child: Text(
                    'common.name'.tr(),
                    style: TextStyle(fontSize: 11, color: tokens.divider),
                  ),
                ),
                Expanded(
                  child: _NameField(
                    name: '${node['name'] ?? ''}',
                    onSubmit: (value) =>
                        ref.read(documentProvider.notifier).dispatch(
                          'node.rename',
                          <String, Object?>{'id': id, 'name': value},
                        ),
                  ),
                ),
              ],
            ),
          ),
          SwitchRow(
            labelKey: 'panel.inspector.visible',
            value: asBool(node['visible'], true),
            onChanged: (value) => ref.read(documentProvider.notifier).dispatch(
              'node.set_visible',
              <String, Object?>{'id': id, 'value': value},
            ),
          ),
          SwitchRow(
            labelKey: 'panel.inspector.locked',
            value: asBool(node['locked']),
            onChanged: (value) => ref.read(documentProvider.notifier).dispatch(
              'node.set_locked',
              <String, Object?>{'id': id, 'value': value},
            ),
          ),

          if (kind == AmNodeKind.drawable) ...<Widget>[
            SectionHeader(titleKey: 'panel.inspector.section.draw'),
            LabeledSlider(
              label: 'panel.inspector.opacity'.tr(),
              value: asDouble(node['opacity'], 1),
              min: 0,
              max: 1,
              defaultValue: 1,
              onChanged: (value) =>
                  ref.read(documentProvider.notifier).dispatch(
                    'drawable.set_opacity',
                    <String, Object?>{'id': id, 'value': value},
                  ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 108,
                    child: Text(
                      'panel.inspector.blend'.tr(),
                      style: TextStyle(fontSize: 11, color: tokens.divider),
                    ),
                  ),
                  Expanded(
                    child: EnumDropdown<AmBlendMode>(
                      value: AmBlendMode.parse(node['blend_mode']),
                      items: AmBlendMode.values,
                      labelOf: (mode) => 'blend.${mode.wire}'.tr(),
                      onChanged: (value) {
                        if (value == null) return;
                        ref.read(documentProvider.notifier).dispatch(
                          'drawable.set_blend',
                          <String, Object?>{'id': id, 'value': value.wire},
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${node['texture'] ?? 'panel.inspector.noTexture'.tr()}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: tokens.divider),
                    ),
                  ),
                  SmallTextButton(
                    labelKey: 'panel.inspector.chooseTexture',
                    icon: Icons.folder_open,
                    onPressed: () => _chooseTexture(context, ref, id),
                  ),
                ],
              ),
            ),
            _uvEditor(context, ref, id, node),
            _maskEditor(context, ref, id, document),
          ],

          if (kind.isDeformer) ...<Widget>[
            SectionHeader(titleKey: 'panel.inspector.section.deformer'),
            KeyValueRow(
              labelKey: 'panel.inspector.rows',
              value: '${asInt(node['rows'])}',
            ),
            KeyValueRow(
              labelKey: 'panel.inspector.cols',
              value: '${asInt(node['cols'])}',
            ),
            KeyValueRow(
              labelKey: 'panel.inspector.controlPoints',
              value: '${asJsonList(node['control_points']).length}',
            ),
          ],

          if (kind == AmNodeKind.drawable) ...<Widget>[
            SectionHeader(titleKey: 'panel.inspector.section.mesh'),
            KeyValueRow(
              labelKey: 'panel.inspector.vertices',
              value: '${asJsonList(mesh?['vertices']).length}',
            ),
            KeyValueRow(
              labelKey: 'panel.inspector.triangles',
              value: '${asJsonList(mesh?['indices']).length ~/ 3}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _uvEditor(
    BuildContext context,
    WidgetRef ref,
    String id,
    Map<String, Object?> node,
  ) {
    final uv = asJsonList(node['uv']);
    final values = <double>[
      uv.isNotEmpty ? asDouble(uv[0]) : 0,
      uv.length > 1 ? asDouble(uv[1]) : 0,
      uv.length > 2 ? asDouble(uv[2]) : 1,
      uv.length > 3 ? asDouble(uv[3]) : 1,
    ];
    const labels = <String>['u', 'v', 'w', 'h'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(titleKey: 'panel.inspector.section.uv'),
        for (var i = 0; i < 4; i++)
          LabeledSlider(
            label: labels[i],
            value: values[i],
            min: 0,
            max: i < 2 ? 1 : 2,
            digits: 3,
            onChanged: (value) {
              final next = <Object?>[...values]..[i] = value;
              ref.read(documentProvider.notifier).dispatch(
                'drawable.set_uv',
                <String, Object?>{'id': id, 'uv': next},
              );
            },
          ),
      ],
    );
  }

  Widget _maskEditor(
    BuildContext context,
    WidgetRef ref,
    String id,
    DocumentState document,
  ) {
    final tokens = AppTheme.of(context);
    final mask = asJsonList(
      document.nodes[id]?['mask'],
    ).map((e) => '$e').toList();
    final candidates = document.nodes.keys
        .where((other) => other != id && !mask.contains(other))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          titleKey: 'panel.inspector.section.mask',
          actions: <Widget>[
            SmallIconButton(
              icon: Icons.add,
              tooltipKey: 'panel.inspector.addMask',
              onPressed: candidates.isEmpty
                  ? null
                  : () => _addMask(context, ref, id, candidates),
            ),
          ],
        ),
        if (mask.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              'panel.inspector.noMask'.tr(),
              style: TextStyle(fontSize: 11, color: tokens.divider),
            ),
          )
        else
          for (final maskId in mask)
            ListRow(
              trailing: SmallIconButton(
                icon: Icons.close,
                tooltipKey: 'panel.inspector.removeMask',
                onPressed: () {
                  final next = mask.where((e) => e != maskId).toList();
                  ref.read(documentProvider.notifier).dispatch(
                    'drawable.set_mask',
                    <String, Object?>{'id': id, 'value': next},
                  );
                },
              ),
              child: Text(
                '${document.nodes[maskId]?['name'] ?? maskId}',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
      ],
    );
  }

  Future<void> _addMask(
    BuildContext context,
    WidgetRef ref,
    String id,
    List<String> candidates,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('panel.inspector.addMask'.tr()),
        children: <Widget>[
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(candidate),
              child: Text(
                '${ref.read(documentProvider).nodes[candidate]?['name'] ?? candidate}',
              ),
            ),
        ],
      ),
    );
    if (choice == null) return;
    final current = asJsonList(
      ref.read(documentProvider).nodes[id]?['mask'],
    ).map((e) => '$e').toList();
    await ref.read(documentProvider.notifier).dispatch(
      'drawable.set_mask',
      <String, Object?>{
        'id': id,
        'value': <Object?>[...current, choice],
      },
    );
  }

  Future<void> _chooseTexture(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final files = await FileService.pickFiles(
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'svg'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    // 有路径就用路径；Web 端用 data URL 直接内联（引擎接入后由引擎解码）。
    final reference =
        file.path ??
        (file.hasBytes
            ? 'data:image/*;base64,${base64Encode(file.bytes!)}'
            : null);
    if (reference == null) return;
    await ref.read(documentProvider.notifier).dispatch(
      'drawable.set_texture',
      <String, Object?>{'id': id, 'texture': reference},
    );
  }
}

class _NameField extends StatefulWidget {
  const _NameField({required this.name, required this.onSubmit});

  final String name;
  final ValueChanged<String> onSubmit;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.name,
  );

  @override
  void didUpdateWidget(covariant _NameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name && _controller.text != widget.name) {
      _controller.text = widget.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    style: const TextStyle(fontSize: 11.5),
    decoration: const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    ),
    onSubmitted: (value) {
      if (value.trim().isNotEmpty) widget.onSubmit(value.trim());
    },
  );
}
