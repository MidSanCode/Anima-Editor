/// 参数面板：分组、范围、默认值、关键点、重命名、删除（AE1-2）。
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

/// 参数面板。
class ParameterPanel extends ConsumerStatefulWidget {
  const ParameterPanel({super.key});

  @override
  ConsumerState<ParameterPanel> createState() => _ParameterPanelState();
}

class _ParameterPanelState extends ConsumerState<ParameterPanel> {
  final Set<String> _collapsedGroups = <String>{};

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final runtime = ref.watch(runtimeProvider);
    final playback = ref.watch(playbackProvider);
    final groups = document.parameterGroups;

    if (document.parameters.isEmpty) {
      return Column(
        children: <Widget>[
          Expanded(
            child: EmptyState(
              icon: Icons.tune,
              titleKey: 'panel.parameter.empty',
              subtitleKey: 'panel.parameter.emptyHint',
              action: FilledButton.tonal(
                onPressed: _createParameter,
                child: Text('panel.parameter.create'.tr()),
              ),
            ),
          ),
          _footer(document),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              for (final entry in groups.entries) ...<Widget>[
                SectionHeader(
                  titleKey: entry.key,
                  actions: <Widget>[
                    SmallIconButton(
                      icon: _collapsedGroups.contains(entry.key)
                          ? Icons.expand_more
                          : Icons.expand_less,
                      tooltipKey: 'panel.parameter.toggleGroup',
                      onPressed: () => setState(() {
                        if (!_collapsedGroups.remove(entry.key)) {
                          _collapsedGroups.add(entry.key);
                        }
                      }),
                    ),
                  ],
                ),
                if (!_collapsedGroups.contains(entry.key))
                  for (final paramId in entry.value)
                    _buildParameter(
                      paramId,
                      document.parameters[paramId] ?? const <String, Object?>{},
                      runtime,
                      playback.recording,
                      tokens,
                    ),
              ],
              if (playback.recording)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'panel.parameter.recordingHint'.tr(),
                    style: TextStyle(fontSize: 10.5, color: tokens.warning),
                  ),
                ),
            ],
          ),
        ),
        _footer(document),
      ],
    );
  }

  Widget _buildParameter(
    String paramId,
    Map<String, Object?> param,
    RuntimeState runtime,
    bool recording,
    AppTokens tokens,
  ) {
    final name = '${param['name'] ?? paramId}';
    final min = asDouble(param['min'], -1);
    final max = asDouble(param['max'], 1);
    final defaultValue = asDouble(param['default']);
    final keys = asJsonList(param['keys']);
    final value = runtime.valueOf(paramId, defaultValue);

    return GestureDetector(
      onSecondaryTap: () => _parameterMenu(paramId, param),
      child: LabeledSlider(
        label: name,
        value: value,
        min: min,
        max: max,
        defaultValue: defaultValue,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (keys.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Tooltip(
                  message: 'panel.parameter.hasKeys'.tr(),
                  child: Icon(
                    Icons.bookmark,
                    size: 12,
                    color: tokens.accentSecondary,
                  ),
                ),
              ),
            SmallIconButton(
              icon: Icons.more_vert,
              tooltipKey: 'panel.parameter.menu',
              onPressed: () => _parameterMenu(paramId, param),
            ),
          ],
        ),
        onChanged: (next) =>
            ref.read(runtimeProvider.notifier).setParam(paramId, next),
        onChangeEnd: recording
            ? (next) {
                final playback = ref.read(playbackProvider);
                final motion =
                    playback.motion ?? ref.read(runtimeProvider).motion;
                if (motion == null) return;
                ref
                    .read(documentProvider.notifier)
                    .dispatch('motion.set_key', <String, Object?>{
                      'motion': motion,
                      'param': paramId,
                      'time': playback.time,
                      'value': next,
                    });
              }
            : null,
      ),
    );
  }

  Widget _footer(DocumentState document) {
    final selection = ref.watch(selectionProvider);
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
            tooltipKey: 'panel.parameter.create',
            onPressed: _createParameter,
          ),
          SmallIconButton(
            icon: Icons.delete_outline,
            tooltipKey: 'common.delete',
            onPressed: selection.primary == null
                ? null
                : () => _deleteParameter(selection.primary!),
          ),
          const Spacer(),
          SmallIconButton(
            icon: Icons.restart_alt,
            tooltipKey: 'panel.parameter.resetAll',
            onPressed: () => ref.read(runtimeProvider.notifier).reset(),
          ),
          Text(
            '${document.parameters.length}',
            style: TextStyle(
              fontSize: 10.5,
              color: AppTheme.of(context).divider,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createParameter() async {
    final name = await promptDialog(
      context,
      titleKey: 'panel.parameter.create',
      labelKey: 'common.name',
      initial: 'Param',
    );
    if (name == null || name.isEmpty) return;
    await ref.read(documentProvider.notifier).dispatch(
      'param.create',
      <String, Object?>{
        'name': name,
        'group': 'ParamGroup',
        'min': -1,
        'max': 1,
        'default': 0,
      },
    );
    await ref.read(runtimeProvider.notifier).load();
  }

  Future<void> _deleteParameter(String id) async {
    final document = ref.read(documentProvider);
    final param = document.parameters[id];
    final ok = await confirmDialog(
      context,
      titleKey: 'panel.parameter.deleteTitle',
      messageKey: 'panel.parameter.deleteMessage',
      args: <String, String>{'name': '${param?['name'] ?? id}'},
    );
    if (!ok) return;
    await ref.read(documentProvider.notifier).dispatch(
      'param.delete',
      <String, Object?>{'id': id},
    );
    await ref.read(runtimeProvider.notifier).load();
  }

  Future<void> _parameterMenu(
    String paramId,
    Map<String, Object?> param,
  ) async {
    final name = '${param['name'] ?? paramId}';
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(Offset.zero);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'rename',
          child: Text('common.rename'.tr()),
        ),
        PopupMenuItem<String>(
          value: 'range',
          child: Text('panel.parameter.editRange'.tr()),
        ),
        PopupMenuItem<String>(
          value: 'default',
          child: Text('panel.parameter.setDefaultCurrent'.tr()),
        ),
        PopupMenuItem<String>(
          value: 'group',
          child: Text('panel.parameter.setGroup'.tr()),
        ),
        PopupMenuItem<String>(
          value: 'keys',
          child: Text('panel.parameter.editKeys'.tr()),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('common.delete'.tr()),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    final document = ref.read(documentProvider.notifier);
    switch (choice) {
      case 'rename':
        final next = await promptDialog(
          context,
          titleKey: 'common.rename',
          labelKey: 'common.name',
          initial: name,
        );
        if (next != null && next.isNotEmpty) {
          await document.dispatch('param.rename', <String, Object?>{
            'id': paramId,
            'name': next,
          });
        }
      case 'range':
        final range = await _askRange(
          asDouble(param['min'], -1),
          asDouble(param['max'], 1),
        );
        if (range != null) {
          await document.dispatch('param.set_range', <String, Object?>{
            'id': paramId,
            'min': range.$1,
            'max': range.$2,
          });
        }
      case 'default':
        final value = ref
            .read(runtimeProvider)
            .valueOf(paramId, asDouble(param['default']));
        await document.dispatch('param.set_default', <String, Object?>{
          'id': paramId,
          'value': value,
        });
      case 'group':
        final group = await promptDialog(
          context,
          titleKey: 'panel.parameter.setGroup',
          labelKey: 'panel.parameter.group',
          initial: '${param['group'] ?? ''}',
        );
        if (group != null && group.isNotEmpty) {
          await document.dispatch('param.set_group', <String, Object?>{
            'id': paramId,
            'group': group,
          });
        }
      case 'keys':
        await _editKeys(paramId, param);
      case 'delete':
        await _deleteParameter(paramId);
    }
  }

  Future<(double, double)?> _askRange(double min, double max) async {
    final minController = TextEditingController(text: '$min');
    final maxController = TextEditingController(text: '$max');
    final result = await showDialog<(double, double)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('panel.parameter.editRange'.tr()),
        content: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: minController,
                decoration: InputDecoration(
                  labelText: 'panel.parameter.min'.tr(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: maxController,
                decoration: InputDecoration(
                  labelText: 'panel.parameter.max'.tr(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              final lo = double.tryParse(minController.text);
              final hi = double.tryParse(maxController.text);
              if (lo == null || hi == null || hi <= lo) {
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop((lo, hi));
            },
            child: Text('common.confirm'.tr()),
          ),
        ],
      ),
    );
    minController.dispose();
    maxController.dispose();
    return result;
  }

  Future<void> _editKeys(String paramId, Map<String, Object?> param) async {
    final controller = TextEditingController(
      text: asJsonList(param['keys']).map((e) => '$e').join(', '),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('panel.parameter.editKeys'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'panel.parameter.keysHint'.tr(),
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'panel.parameter.keys'.tr(),
              ),
            ),
          ],
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
    if (result == null) return;
    final keys =
        result
            .split(RegExp(r'[,\s]+'))
            .where((e) => e.trim().isNotEmpty)
            .map((e) => double.tryParse(e.trim()))
            .whereType<double>()
            .toList()
          ..sort();
    await ref.read(documentProvider.notifier).dispatch(
      'param.set_keys',
      <String, Object?>{'id': paramId, 'keys': keys},
    );
  }
}
