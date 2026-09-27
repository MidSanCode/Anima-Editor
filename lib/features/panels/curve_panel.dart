/// 曲线编辑器：关键帧插值、切线、增删关键帧（AE3-2）。
library;

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_types.dart';
import '../../core/engine/local_eval.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/runtime_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

/// 曲线编辑器面板。
class CurvePanel extends ConsumerStatefulWidget {
  const CurvePanel({super.key});

  @override
  ConsumerState<CurvePanel> createState() => _CurvePanelState();
}

class _CurvePanelState extends ConsumerState<CurvePanel> {
  double? _dragTime;
  double? _dragValue;
  double? _dragStartTime;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final playback = ref.watch(playbackProvider);
    final runtime = ref.watch(runtimeProvider);
    final motion = document.motions
        .map(asJsonMap)
        .firstWhereOrNull((item) => '${item['name']}' == playback.motion);
    if (motion == null) {
      return EmptyState(
        icon: Icons.show_chart,
        titleKey: 'panel.curve.noMotion',
        subtitleKey: 'panel.curve.noMotionHint',
      );
    }
    final curves = asJsonList(motion['curves']).map(asJsonMap).toList();
    final params = curves.map((curve) => '${curve['param']}').toList();
    final selectedParam = playback.selectedKeys
        .map((key) => key.split('@').first)
        .firstWhereOrNull((param) => params.contains(param));
    final curve = curves.firstWhereOrNull(
      (item) => '${item['param']}' == selectedParam,
    );
    final keys = curve == null
        ? const <Map<String, Object?>>[]
        : asJsonList(curve['keys']).map(asJsonMap).toList();
    final paramId = selectedParam ?? (params.isEmpty ? null : params.first);
    final param = paramId == null ? null : document.parameters[paramId];
    final min = asDouble(param?['min'], -1);
    final max = asDouble(param?['max'], 1);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: params.isEmpty
                    ? Text(
                        'panel.curve.noCurve'.tr(),
                        style: TextStyle(fontSize: 11, color: tokens.textMuted),
                      )
                    : EnumDropdown<String>(
                        value: paramId!,
                        items: params,
                        labelOf: (id) =>
                            '${document.parameters[id]?['name'] ?? id}',
                        onChanged: (id) {
                          if (id == null) return;
                          ref
                              .read(playbackProvider.notifier)
                              .toggleKeySelection('$id@0');
                        },
                      ),
              ),
              SmallIconButton(
                icon: Icons.add,
                tooltipKey: 'panel.curve.addKey',
                onPressed: paramId == null
                    ? null
                    : () => ref
                          .read(documentProvider.notifier)
                          .dispatch('motion.set_key', <String, Object?>{
                            'motion': '${motion['name']}',
                            'param': paramId,
                            'time': playback.time,
                            'value': runtime.valueOf(
                              paramId,
                              asDouble(param?['default']),
                            ),
                          }),
              ),
            ],
          ),
        ),
        Expanded(
          child: paramId == null
              ? EmptyState(
                  icon: Icons.show_chart,
                  titleKey: 'panel.curve.noCurve',
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _CurveGraph(
                    keys: keys,
                    duration: playback.duration <= 0 ? 1 : playback.duration,
                    min: min,
                    max: max,
                    time: playback.time,
                    dragTime: _dragTime,
                    dragValue: _dragValue,
                    dragStartTime: _dragStartTime,
                    onSeek: (time) {
                      ref.read(playbackProvider.notifier).setTime(time);
                      ref.read(runtimeProvider.notifier).seek(time);
                    },
                    onKeySelected: (key) {
                      ref
                          .read(playbackProvider.notifier)
                          .toggleKeySelection(
                            '$paramId@${asDouble(key['time'])}',
                          );
                    },
                    onKeyDragStart: (key) {
                      setState(() {
                        _dragStartTime = asDouble(key['time']);
                        _dragTime = _dragStartTime;
                        _dragValue = asDouble(key['value']);
                      });
                    },
                    onKeyDragUpdate: (time, value) {
                      setState(() {
                        _dragTime = time;
                        _dragValue = value;
                      });
                    },
                    onKeyDragEnd: () async {
                      final start = _dragStartTime;
                      final time = _dragTime;
                      final value = _dragValue;
                      setState(() {
                        _dragStartTime = null;
                        _dragTime = null;
                        _dragValue = null;
                      });
                      if (start == null || time == null || value == null) {
                        return;
                      }
                      final key = keys.firstWhereOrNull(
                        (item) => (asDouble(item['time']) - start).abs() < 1e-6,
                      );
                      if (key == null) return;
                      final controller = ref.read(documentProvider.notifier);
                      await controller.dispatch(
                        'motion.remove_key',
                        <String, Object?>{
                          'motion': '${motion['name']}',
                          'param': paramId,
                          'time': start,
                        },
                      );
                      await controller
                          .dispatch('motion.set_key', <String, Object?>{
                            'motion': '${motion['name']}',
                            'param': paramId,
                            'time': time,
                            'value': value,
                            'interp': key['interp'],
                            'in_tangent': asDouble(key['in_tangent']),
                            'out_tangent': asDouble(key['out_tangent']),
                          });
                    },
                  ),
                ),
        ),
        if (keys.isNotEmpty && paramId != null)
          _keyEditor(motion, paramId, keys, document),
      ],
    );
  }

  Widget _keyEditor(
    Map<String, Object?> motion,
    String paramId,
    List<Map<String, Object?>> keys,
    DocumentState document,
  ) {
    final tokens = AppTheme.of(context);
    final selected = ref.watch(playbackProvider).selectedKeys;
    final key = keys.firstWhereOrNull(
      (item) => selected.contains('$paramId@${asDouble(item['time'])}'),
    );
    if (key == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'panel.curve.selectKey'.tr(),
          style: TextStyle(fontSize: 11, color: tokens.textMuted),
        ),
      );
    }
    final time = asDouble(key['time']);
    final interp = AmInterpolation.parse(key['interp']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 108,
                child: Text(
                  'panel.curve.interp'.tr(),
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
              ),
              Expanded(
                child: EnumDropdown<AmInterpolation>(
                  value: interp,
                  items: AmInterpolation.values,
                  labelOf: (value) => 'interp.${value.wire}'.tr(),
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(documentProvider.notifier)
                        .dispatch('motion.set_key', <String, Object?>{
                          'motion': '${motion['name']}',
                          'param': paramId,
                          'time': time,
                          'value': asDouble(key['value']),
                          'interp': value.wire,
                          'in_tangent': asDouble(key['in_tangent']),
                          'out_tangent': asDouble(key['out_tangent']),
                        });
                  },
                ),
              ),
              SmallIconButton(
                icon: Icons.delete_outline,
                tooltipKey: 'panel.curve.deleteKey',
                onPressed: () => ref.read(documentProvider.notifier).dispatch(
                  'motion.remove_key',
                  <String, Object?>{
                    'motion': '${motion['name']}',
                    'param': paramId,
                    'time': time,
                  },
                ),
              ),
            ],
          ),
          if (interp == AmInterpolation.bezier) ...<Widget>[
            LabeledSlider(
              label: 'panel.curve.inTangent'.tr(),
              value: asDouble(key['in_tangent']),
              min: -5,
              max: 5,
              defaultValue: 0,
              onChanged: (value) =>
                  _updateKey(motion, paramId, key, inTangent: value),
            ),
            LabeledSlider(
              label: 'panel.curve.outTangent'.tr(),
              value: asDouble(key['out_tangent']),
              min: -5,
              max: 5,
              defaultValue: 0,
              onChanged: (value) =>
                  _updateKey(motion, paramId, key, outTangent: value),
            ),
          ],
          KeyValueRow(
            labelKey: 'panel.curve.keyTime',
            value: time.toStringAsFixed(3),
          ),
          KeyValueRow(
            labelKey: 'panel.curve.keyValue',
            value: asDouble(key['value']).toStringAsFixed(3),
          ),
        ],
      ),
    );
  }

  void _updateKey(
    Map<String, Object?> motion,
    String paramId,
    Map<String, Object?> key, {
    double? inTangent,
    double? outTangent,
  }) {
    ref
        .read(documentProvider.notifier)
        .dispatch('motion.set_key', <String, Object?>{
          'motion': '${motion['name']}',
          'param': paramId,
          'time': asDouble(key['time']),
          'value': asDouble(key['value']),
          'interp': key['interp'],
          'in_tangent': inTangent ?? asDouble(key['in_tangent']),
          'out_tangent': outTangent ?? asDouble(key['out_tangent']),
        });
  }
}

class _CurveGraph extends StatelessWidget {
  const _CurveGraph({
    required this.keys,
    required this.duration,
    required this.min,
    required this.max,
    required this.time,
    required this.dragTime,
    required this.dragValue,
    required this.dragStartTime,
    required this.onSeek,
    required this.onKeySelected,
    required this.onKeyDragStart,
    required this.onKeyDragUpdate,
    required this.onKeyDragEnd,
  });

  final List<Map<String, Object?>> keys;
  final double duration;
  final double min;
  final double max;
  final double time;
  final double? dragTime;
  final double? dragValue;
  final double? dragStartTime;
  final ValueChanged<double> onSeek;
  final ValueChanged<Map<String, Object?>> onKeySelected;
  final ValueChanged<Map<String, Object?>> onKeyDragStart;
  final void Function(double time, double value) onKeyDragUpdate;
  final VoidCallback onKeyDragEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        double toX(double value) => size.width * (value / duration);
        double toY(double value) =>
            size.height -
            size.height * ((value - min) / (max - min == 0 ? 1 : max - min));

        Map<String, Object?>? nearest(Offset position) {
          Map<String, Object?>? best;
          var bestDistance = 12.0;
          for (final key in keys) {
            final point = Offset(
              toX(asDouble(key['time'])),
              toY(asDouble(key['value'])),
            );
            final distance = (point - position).distance;
            if (distance <= bestDistance) {
              bestDistance = distance;
              best = key;
            }
          }
          return best;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final key = nearest(details.localPosition);
            if (key != null) {
              onKeySelected(key);
              return;
            }
            onSeek(
              (details.localPosition.dx / size.width * duration).clamp(
                0.0,
                duration,
              ),
            );
          },
          onPanStart: (details) {
            final key = nearest(details.localPosition);
            if (key != null) onKeyDragStart(key);
          },
          onPanUpdate: (details) {
            if (dragStartTime == null) return;
            final nextTime = (details.localPosition.dx / size.width * duration)
                .clamp(0.0, duration);
            final ratio =
                1 - (details.localPosition.dy / size.height).clamp(0.0, 1.0);
            onKeyDragUpdate(nextTime, min + ratio * (max - min));
          },
          onPanEnd: (_) => onKeyDragEnd(),
          child: CustomPaint(
            painter: _CurvePainter(
              keys: keys,
              duration: duration,
              min: min,
              max: max,
              time: time,
              dragTime: dragTime,
              dragValue: dragValue,
              dragStartTime: dragStartTime,
              grid: tokens.gridLine,
              curveColor: Theme.of(context).colorScheme.primary,
              keyColor: tokens.accentSecondary,
              playhead: tokens.selectionStroke,
            ),
            size: size,
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  const _CurvePainter({
    required this.keys,
    required this.duration,
    required this.min,
    required this.max,
    required this.time,
    required this.dragTime,
    required this.dragValue,
    required this.dragStartTime,
    required this.grid,
    required this.curveColor,
    required this.keyColor,
    required this.playhead,
  });

  final List<Map<String, Object?>> keys;
  final double duration;
  final double min;
  final double max;
  final double time;
  final double? dragTime;
  final double? dragValue;
  final double? dragStartTime;
  final Color grid;
  final Color curveColor;
  final Color keyColor;
  final Color playhead;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 0; i <= 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    double toX(double value) => size.width * (value / duration).clamp(0.0, 1.0);
    double toY(double value) =>
        size.height -
        size.height *
            ((value - min) / (max - min == 0 ? 1 : max - min)).clamp(0.0, 1.0);

    final effective = <Map<String, Object?>>[
      for (final key in keys)
        if (dragStartTime != null &&
            (asDouble(key['time']) - dragStartTime!).abs() < 1e-6)
          <String, Object?>{
            ...key,
            'time': dragTime ?? key['time'],
            'value': dragValue ?? key['value'],
          }
        else
          key,
    ]..sort((a, b) => asDouble(a['time']).compareTo(asDouble(b['time'])));

    if (effective.isNotEmpty) {
      final path = Path();
      final samples = math.max(2, size.width ~/ 3);
      for (var i = 0; i <= samples; i++) {
        final sampleTime = duration * i / samples;
        final value = evaluateCurve(effective, sampleTime);
        final point = Offset(toX(sampleTime), toY(value));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = curveColor,
      );
    }

    for (final key in effective) {
      final center = Offset(
        toX(asDouble(key['time'])),
        toY(asDouble(key['value'])),
      );
      canvas.drawCircle(center, 4, Paint()..color = keyColor);
      canvas.drawCircle(
        center,
        4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.7),
      );
    }

    final head = toX(time);
    canvas.drawLine(
      Offset(head, 0),
      Offset(head, size.height),
      Paint()
        ..color = playhead
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.keys != keys ||
      oldDelegate.dragTime != dragTime ||
      oldDelegate.dragValue != dragValue;
}
