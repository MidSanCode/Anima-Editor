/// 关键形（keyform）面板：记录、删除、混合类型、取值编辑（AE1-4）。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_types.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/runtime_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

/// 关键形面板。
class KeyformPanel extends ConsumerWidget {
  const KeyformPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final selection = ref.watch(selectionProvider);
    final id = selection.primary;
    if (id == null) {
      return EmptyState(
        icon: Icons.bookmark_border,
        titleKey: 'panel.keyform.empty',
        subtitleKey: 'panel.keyform.emptyHint',
      );
    }
    final keyforms =
        ref.watch(keyformsProvider(id)).value ?? const <String, Object?>{};
    final runtime = ref.watch(runtimeProvider);
    final playback = ref.watch(playbackProvider);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              SectionHeader(
                titleKey: 'panel.keyform.section.record',
                actions: <Widget>[
                  SmallIconButton(
                    icon: playback.recording
                        ? Icons.fiber_manual_record
                        : Icons.fiber_manual_record_outlined,
                    tooltipKey: 'panel.keyform.toggleRecording',
                    selected: playback.recording,
                    onPressed: () => ref
                        .read(playbackProvider.notifier)
                        .setRecording(!playback.recording),
                  ),
                ],
              ),
              if (keyforms.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'panel.keyform.none'.tr(),
                    style: TextStyle(fontSize: 11, color: tokens.textMuted),
                  ),
                )
              else
                for (final entry in keyforms.entries)
                  _buildParamGroup(
                    context,
                    ref,
                    id,
                    entry.key,
                    asJsonMap(entry.value),
                    runtime,
                  ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.divider)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'panel.keyform.recordHint'.tr(),
                  style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
                ),
              ),
              SmallIconButton(
                icon: Icons.delete_sweep,
                tooltipKey: 'panel.keyform.clearAll',
                onPressed: keyforms.isEmpty
                    ? null
                    : () async {
                        for (final paramId in keyforms.keys) {
                          await ref.read(documentProvider.notifier).dispatch(
                            'keyform.delete',
                            <String, Object?>{'id': id, 'param': paramId},
                          );
                        }
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParamGroup(
    BuildContext context,
    WidgetRef ref,
    String nodeId,
    String paramId,
    Map<String, Object?> group,
    RuntimeState runtime,
  ) {
    final tokens = AppTheme.of(context);
    final document = ref.read(documentProvider);
    final param = document.parameters[paramId];
    final name = '${param?['name'] ?? paramId}';
    final blend = AmKeyformBlend.parse(group['blend_type']);
    final keys = asJsonList(group['keys']);
    final currentValue = runtime.valueOf(paramId, asDouble(param?['default']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          titleKey: name,
          actions: <Widget>[
            SmallIconButton(
              icon: Icons.add,
              tooltipKey: 'panel.keyform.recordCurrent',
              onPressed: () => ref.read(documentProvider.notifier).dispatch(
                'keyform.record',
                <String, Object?>{
                  'id': nodeId,
                  'param': paramId,
                  'value': currentValue,
                },
              ),
            ),
            SmallIconButton(
              icon: Icons.delete_outline,
              tooltipKey: 'panel.keyform.deleteParam',
              onPressed: () => ref.read(documentProvider.notifier).dispatch(
                'keyform.delete',
                <String, Object?>{'id': nodeId, 'param': paramId},
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 108,
                child: Text(
                  'panel.keyform.blendType'.tr(),
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
              ),
              Expanded(
                child: EnumDropdown<AmKeyformBlend>(
                  value: blend,
                  items: AmKeyformBlend.values,
                  labelOf: (value) => 'keyform.blend.${value.wire}'.tr(),
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(documentProvider.notifier).dispatch(
                      'keyform.set_blend_type',
                      <String, Object?>{
                        'id': nodeId,
                        'param': paramId,
                        'value': value.wire,
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        for (final key in keys)
          _KeyformRow(
            nodeId: nodeId,
            paramId: paramId,
            record: asJsonMap(key),
            current: currentValue,
          ),
      ],
    );
  }
}

class _KeyformRow extends ConsumerWidget {
  const _KeyformRow({
    required this.nodeId,
    required this.paramId,
    required this.record,
    required this.current,
  });

  final String nodeId;
  final String paramId;
  final Map<String, Object?> record;
  final double current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final value = asDouble(record['value']);
    final vertices = asJsonList(record['vertices']);
    final transform = asJsonMap(record['transform']);
    final isCurrent = (value - current).abs() < 1e-6;
    final hasDelta = vertices.any(
      (v) =>
          asDouble(asJsonList(v).isNotEmpty ? asJsonList(v)[0] : 0) != 0 ||
          asDouble(asJsonList(v).length > 1 ? asJsonList(v)[1] : 0) != 0,
    );

    return ListRow(
      selected: isCurrent,
      onTap: () => ref.read(runtimeProvider.notifier).setParam(paramId, value),
      leading: Icon(
        hasDelta ? Icons.edit : Icons.bookmark,
        size: 12,
        color: hasDelta ? tokens.accentSecondary : tokens.textMuted,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SmallIconButton(
            icon: Icons.edit_note,
            tooltipKey: 'panel.keyform.overwrite',
            onPressed: () => ref.read(documentProvider.notifier).dispatch(
              'keyform.record',
              <String, Object?>{'id': nodeId, 'param': paramId, 'value': value},
            ),
          ),
          SmallIconButton(
            icon: Icons.delete_outline,
            tooltipKey: 'panel.keyform.deleteKey',
            onPressed: () => ref.read(documentProvider.notifier).dispatch(
              'keyform.delete',
              <String, Object?>{'id': nodeId, 'param': paramId, 'value': value},
            ),
          ),
        ],
      ),
      child: Text(
        '${value.toStringAsFixed(2)}'
        '${transform.isEmpty ? '' : ' · ${'panel.keyform.hasTransform'.tr()}'}',
        style: const TextStyle(fontSize: 11.5),
      ),
    );
  }
}
