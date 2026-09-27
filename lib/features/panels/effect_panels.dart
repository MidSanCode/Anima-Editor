/// 效果类面板：物理、表情、姿势、口型、模型设置（AE1-5 / AE4-2~4）。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_types.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/runtime_controller.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

// ---------------------------------------------------------------------------
// 物理
// ---------------------------------------------------------------------------

/// 物理面板。
class PhysicsPanel extends ConsumerWidget {
  const PhysicsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final runtime = ref.watch(runtimeProvider);
    final settings = document.physics.map(asJsonMap).toList();

    return Column(
      children: <Widget>[
        SwitchRow(
          labelKey: 'panel.physics.enabled',
          value: runtime.physicsEnabled,
          onChanged: (value) =>
              ref.read(runtimeProvider.notifier).setPhysics(value),
        ),
        SectionHeader(
          titleKey: 'panel.physics.section.settings',
          actions: <Widget>[
            SmallIconButton(
              icon: Icons.add,
              tooltipKey: 'panel.physics.add',
              onPressed: () => ref
                  .read(documentProvider.notifier)
                  .dispatch('physics.add_setting', <String, Object?>{
                    'name': 'physics${settings.length + 1}',
                    'inputs': <Object?>[],
                    'outputs': <Object?>[],
                  }),
            ),
          ],
        ),
        Expanded(
          child: settings.isEmpty
              ? EmptyState(
                  icon: Icons.waves,
                  titleKey: 'panel.physics.empty',
                  subtitleKey: 'panel.physics.emptyHint',
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    for (final setting in settings)
                      _PhysicsSetting(
                        setting: setting,
                        // 物理绑定存的是参数 id（引擎要求 id）；这里带上名字，
                        // 选择框和列表显示名字，落库仍是 id。
                        parameters: <String, String>{
                          for (final entry in document.parameters.entries)
                            entry.key: '${asJsonMap(entry.value)['name']}',
                        },
                      ),
                  ],
                ),
        ),
        if (settings.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'panel.physics.hint'.tr(),
              style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
            ),
          ),
      ],
    );
  }
}

class _PhysicsSetting extends ConsumerWidget {
  const _PhysicsSetting({required this.setting, required this.parameters});

  final Map<String, Object?> setting;

  /// 参数 id → 显示名。引擎的物理输入/输出引用的是参数 **id**，
  /// 但 id 是 UUID，直接显示没法看。
  final Map<String, String> parameters;

  String _label(String id) => parameters[id] ?? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final id = '${setting['id']}';
    final pendulum = asJsonMap(setting['pendulum']);
    final inputs = asJsonList(setting['inputs']).map((e) => '$e').toList();
    final outputs = asJsonList(setting['outputs']).map((e) => '$e').toList();

    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(
        '${setting['name'] ?? id}',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: SmallIconButton(
        icon: Icons.delete_outline,
        tooltipKey: 'common.delete',
        onPressed: () => ref.read(documentProvider.notifier).dispatch(
          'physics.remove_setting',
          <String, Object?>{'id': id},
        ),
      ),
      children: <Widget>[
        LabeledSlider(
          label: 'panel.physics.length'.tr(),
          value: asDouble(pendulum['length'], 20),
          min: 1,
          max: 200,
          onChanged: (value) => ref.read(documentProvider.notifier).dispatch(
            'physics.set_property',
            <String, Object?>{
              'id': id,
              'path': 'pendulum',
              'value': <String, Object?>{...pendulum, 'length': value},
            },
          ),
        ),
        LabeledSlider(
          label: 'panel.physics.frequency'.tr(),
          value: asDouble(pendulum['frequency'], 1.2),
          min: 0.1,
          max: 10,
          onChanged: (value) => ref.read(documentProvider.notifier).dispatch(
            'physics.set_property',
            <String, Object?>{
              'id': id,
              'path': 'pendulum',
              'value': <String, Object?>{...pendulum, 'frequency': value},
            },
          ),
        ),
        LabeledSlider(
          label: 'panel.physics.damping'.tr(),
          value: asDouble(pendulum['damping'], 0.3),
          min: 0,
          max: 1,
          onChanged: (value) => ref.read(documentProvider.notifier).dispatch(
            'physics.set_property',
            <String, Object?>{
              'id': id,
              'path': 'pendulum',
              'value': <String, Object?>{...pendulum, 'damping': value},
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'panel.physics.inputs'.tr(),
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
              ),
              Expanded(
                child: Text(
                  inputs.isEmpty
                      ? '—'
                      : inputs.map(_label).join(', '),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              SmallIconButton(
                icon: Icons.link,
                tooltipKey: 'panel.physics.bindInput',
                onPressed: parameters.isEmpty
                    ? null
                    : () => _bind(context, ref, id, parameters, inputs, true),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'panel.physics.outputs'.tr(),
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
              ),
              Expanded(
                child: Text(
                  outputs.isEmpty
                      ? '—'
                      : outputs.map(_label).join(', '),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              SmallIconButton(
                icon: Icons.link,
                tooltipKey: 'panel.physics.bindOutput',
                onPressed: parameters.isEmpty
                    ? null
                    : () => _bind(context, ref, id, parameters, outputs, false),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _bind(
    BuildContext context,
    WidgetRef ref,
    String id,
    Map<String, String> parameters,
    List<String> current,
    bool isInput,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          (isInput ? 'panel.physics.bindInput' : 'panel.physics.bindOutput')
              .tr(),
        ),
        children: <Widget>[
          // 选项显示参数名，选中后存参数 id（引擎要求 id）。
          for (final entry in parameters.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    );
    if (choice == null) return;
    final next = <Object?>[...current, choice];
    await ref.read(documentProvider.notifier).dispatch(
      'physics.set_property',
      <String, Object?>{
        'id': id,
        'path': isInput ? 'inputs' : 'outputs',
        'value': next,
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 表情
// ---------------------------------------------------------------------------

/// 表情面板。
class ExpressionPanel extends ConsumerWidget {
  const ExpressionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final runtime = ref.watch(runtimeProvider);
    final expressions = document.expressions.map(asJsonMap).toList();

    return Column(
      children: <Widget>[
        SectionHeader(
          titleKey: 'panel.expression.section.list',
          actions: <Widget>[
            SmallIconButton(
              icon: Icons.add,
              tooltipKey: 'panel.expression.create',
              onPressed: () async {
                final name = await promptDialog(
                  context,
                  titleKey: 'panel.expression.create',
                  labelKey: 'common.name',
                  initial: 'Expression${expressions.length + 1}',
                );
                if (name == null || name.isEmpty) return;
                await ref.read(documentProvider.notifier).dispatch(
                  'expression.create',
                  <String, Object?>{
                    'name': name,
                    'params': <String, Object?>{},
                  },
                );
              },
            ),
            SmallIconButton(
              icon: Icons.clear,
              tooltipKey: 'panel.expression.clear',
              onPressed: () =>
                  ref.read(runtimeProvider.notifier).setExpression(null),
            ),
          ],
        ),
        Expanded(
          child: expressions.isEmpty
              ? EmptyState(
                  icon: Icons.emoji_emotions_outlined,
                  titleKey: 'panel.expression.empty',
                  subtitleKey: 'panel.expression.emptyHint',
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    for (final expression in expressions)
                      _ExpressionTile(
                        expression: expression,
                        selected: runtime.expression == '${expression['name']}',
                      ),
                  ],
                ),
        ),
        if (expressions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'panel.expression.hint'.tr(),
              style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
            ),
          ),
      ],
    );
  }
}

class _ExpressionTile extends ConsumerWidget {
  const _ExpressionTile({required this.expression, required this.selected});

  final Map<String, Object?> expression;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final name = '${expression['name']}';
    final params = asJsonMap(expression['params']);
    final document = ref.watch(documentProvider);

    return ExpansionTile(
      dense: true,
      initiallyExpanded: selected,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(
        name,
        style: TextStyle(
          fontSize: 11.5,
          color: selected ? tokens.selectionStroke : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SmallIconButton(
            icon: Icons.play_arrow,
            tooltipKey: 'panel.expression.apply',
            onPressed: () =>
                ref.read(runtimeProvider.notifier).setExpression(name),
          ),
          SmallIconButton(
            icon: Icons.delete_outline,
            tooltipKey: 'common.delete',
            onPressed: () => ref.read(documentProvider.notifier).dispatch(
              'expression.delete',
              <String, Object?>{'name': name},
            ),
          ),
        ],
      ),
      children: <Widget>[
        for (final paramId in document.parameters.keys)
          LabeledSlider(
            label: '${document.parameters[paramId]?['name'] ?? paramId}',
            value: asDouble(params[paramId]),
            min: asDouble(document.parameters[paramId]?['min'], -1),
            max: asDouble(document.parameters[paramId]?['max'], 1),
            defaultValue: 0,
            onChanged: (value) => ref.read(documentProvider.notifier).dispatch(
              'expression.set_param',
              <String, Object?>{'name': name, 'param': paramId, 'value': value},
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 姿势
// ---------------------------------------------------------------------------

/// 姿势面板。
class PosePanel extends ConsumerWidget {
  const PosePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final poses = document.pose.map(asJsonMap).toList();

    return Column(
      children: <Widget>[
        SectionHeader(
          titleKey: 'panel.pose.section.list',
          actions: <Widget>[
            SmallIconButton(
              icon: Icons.add,
              tooltipKey: 'panel.pose.add',
              onPressed: () async {
                final name = await promptDialog(
                  context,
                  titleKey: 'panel.pose.add',
                  labelKey: 'common.name',
                  initial: 'Pose${poses.length + 1}',
                );
                if (name == null || name.isEmpty) return;
                final runtime = ref.read(runtimeProvider);
                await ref.read(documentProvider.notifier).dispatch(
                  'pose.add',
                  <String, Object?>{'name': name, 'params': runtime.params},
                );
              },
            ),
          ],
        ),
        Expanded(
          child: poses.isEmpty
              ? EmptyState(
                  icon: Icons.accessibility_new,
                  titleKey: 'panel.pose.empty',
                  subtitleKey: 'panel.pose.emptyHint',
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    for (final pose in poses)
                      ListRow(
                        onTap: () => ref
                            .read(runtimeProvider.notifier)
                            .setParams(<String, double>{
                              for (final entry in asJsonMap(
                                pose['params'],
                              ).entries)
                                entry.key: asDouble(entry.value),
                            }),
                        leading: const Icon(Icons.accessibility_new, size: 13),
                        trailing: SmallIconButton(
                          icon: Icons.delete_outline,
                          tooltipKey: 'common.delete',
                          onPressed: () =>
                              ref.read(documentProvider.notifier).dispatch(
                                'pose.remove',
                                <String, Object?>{'id': pose['id']},
                              ),
                        ),
                        child: Text(
                          '${pose['name'] ?? pose['id']}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'panel.pose.hint'.tr(),
            style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 口型
// ---------------------------------------------------------------------------

/// 口型同步面板。
class LipsyncPanel extends ConsumerWidget {
  const LipsyncPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final runtime = ref.watch(runtimeProvider);
    final document = ref.watch(documentProvider);
    final mouthParams = document.parameters.entries
        .where((entry) {
          final name = '${entry.value['name']}'.toLowerCase();
          return name.contains('mouth') || name.contains('口');
        })
        .map((entry) => entry.key)
        .toList();

    return PanelScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(titleKey: 'panel.lipsync.section'),
          SwitchRow(
            labelKey: 'panel.lipsync.enabled',
            value: runtime.lipsyncEnabled,
            onChanged: (value) =>
                ref.read(runtimeProvider.notifier).setLipsync(enabled: value),
          ),
          LabeledSlider(
            label: 'panel.lipsync.amplitude'.tr(),
            value: runtime.lipsyncAmplitude,
            min: 0,
            max: 1,
            defaultValue: 0,
            onChanged: (value) =>
                ref.read(runtimeProvider.notifier).setLipsync(amplitude: value),
          ),
          if (mouthParams.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'panel.lipsync.noMouthParam'.tr(),
                style: TextStyle(fontSize: 11, color: tokens.warning),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'panel.lipsync.mouthParam'.tr(
                  namedArgs: <String, String>{
                    'name':
                        '${document.parameters[mouthParams.first]?['name']}',
                  },
                ),
                style: TextStyle(fontSize: 11, color: tokens.textMuted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'panel.lipsync.hint'.tr(),
              style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 模型设置
// ---------------------------------------------------------------------------

/// 模型设置面板（画布、背景、单位、元信息）。
class ModelSettingsPanel extends ConsumerWidget {
  const ModelSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final settings = document.settings;
    final config = document.config;
    final background = asJsonList(settings['background']);

    return PanelScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(titleKey: 'panel.model.section.canvas'),
          LabeledSlider(
            label: 'panel.model.canvasWidth'.tr(),
            value: asDouble(settings['canvas_width'], 1280),
            min: 64,
            max: 4096,
            digits: 0,
            onChanged: (value) => _set(ref, 'canvas_width', value),
          ),
          LabeledSlider(
            label: 'panel.model.canvasHeight'.tr(),
            value: asDouble(settings['canvas_height'], 720),
            min: 64,
            max: 4096,
            digits: 0,
            onChanged: (value) => _set(ref, 'canvas_height', value),
          ),
          LabeledSlider(
            label: 'panel.model.pixelsPerUnit'.tr(),
            value: asDouble(settings['pixels_per_unit'], 1),
            min: 0.1,
            max: 10,
            onChanged: (value) => _set(ref, 'pixels_per_unit', value),
          ),
          SectionHeader(titleKey: 'panel.model.section.background'),
          for (var i = 0; i < 4; i++)
            LabeledSlider(
              label: <String>['R', 'G', 'B', 'A'][i],
              value: background.length > i ? asDouble(background[i]) : 0,
              min: 0,
              max: 1,
              onChanged: (value) {
                final next = <double>[
                  for (var j = 0; j < 4; j++)
                    background.length > j ? asDouble(background[j]) : 0,
                ]..[i] = value;
                _set(ref, 'background', next);
              },
            ),
          SectionHeader(titleKey: 'panel.model.section.meta'),
          KeyValueRow(
            labelKey: 'panel.model.name',
            value: '${config['name'] ?? '—'}',
          ),
          KeyValueRow(
            labelKey: 'panel.model.displayName',
            value: '${config['display_name'] ?? '—'}',
          ),
          KeyValueRow(
            labelKey: 'panel.model.author',
            value: '${config['author'] ?? '—'}',
          ),
          KeyValueRow(
            labelKey: 'panel.model.version',
            value: '${config['version'] ?? '—'}',
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'panel.model.hint'.tr(),
              style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  void _set(WidgetRef ref, String key, Object? value) {
    ref.read(documentProvider.notifier).dispatch(
      'settings.set',
      <String, Object?>{
        'settings': <String, Object?>{key: value},
      },
    );
  }
}
