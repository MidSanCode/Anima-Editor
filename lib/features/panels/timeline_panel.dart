/// 时间轴面板：动作管理、播放控制、关键帧编辑（AE3-1）。
library;

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_types.dart';
import '../../core/i18n/l10n.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/runtime_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

/// 时间轴面板。
class TimelinePanel extends ConsumerWidget {
  const TimelinePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final playback = ref.watch(playbackProvider);
    final runtime = ref.watch(runtimeProvider);
    final motions = document.motions.map(asJsonMap).toList();
    final current = motions.firstWhereOrNull(
      (motion) => '${motion['name']}' == playback.motion,
    );

    return Column(
      children: <Widget>[
        _header(context, ref, motions, playback, current, runtime),
        Container(height: 1, color: tokens.divider),
        Expanded(
          child: current == null
              ? EmptyState(
                  icon: Icons.timeline,
                  titleKey: 'panel.timeline.noMotion',
                  subtitleKey: 'panel.timeline.noMotionHint',
                )
              : _tracks(context, ref, current, playback),
        ),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, Object?>> motions,
    PlaybackState playback,
    Map<String, Object?>? current,
    RuntimeState runtime,
  ) {
    final tokens = AppTheme.of(context);
    final playbackController = ref.read(playbackProvider.notifier);
    final documentController = ref.read(documentProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 130,
                child: motions.isEmpty
                    ? Text(
                        'panel.timeline.noMotion'.tr(),
                        style: TextStyle(fontSize: 11, color: tokens.textMuted),
                      )
                    : EnumDropdown<String>(
                        value: playback.motion ?? '${motions.first['name']}',
                        items: motions
                            .map((motion) => '${motion['name']}')
                            .toList(),
                        labelOf: (name) => name,
                        onChanged: (name) {
                          if (name == null) return;
                          playbackController.selectMotion(name);
                          ref
                              .read(runtimeProvider.notifier)
                              .play(name, loop: playback.loop);
                        },
                      ),
              ),
              SmallIconButton(
                icon: Icons.add,
                tooltipKey: 'panel.timeline.createMotion',
                onPressed: () async {
                  final name = await promptDialog(
                    context,
                    titleKey: 'panel.timeline.createMotion',
                    labelKey: 'common.name',
                    initial: 'Motion${motions.length + 1}',
                  );
                  if (name == null || name.isEmpty) return;
                  await documentController.dispatch(
                    'motion.create',
                    <String, Object?>{'name': name, 'duration': 3},
                  );
                  playbackController.selectMotion(name);
                },
              ),
              SmallIconButton(
                icon: Icons.delete_outline,
                tooltipKey: 'panel.timeline.deleteMotion',
                onPressed: playback.motion == null
                    ? null
                    : () async {
                        final ok = await confirmDialog(
                          context,
                          titleKey: 'panel.timeline.deleteMotion',
                          messageKey: 'panel.timeline.deleteMotionMessage',
                          args: <String, String>{'name': playback.motion!},
                        );
                        if (!ok) return;
                        await documentController.dispatch(
                          'motion.delete',
                          <String, Object?>{'motion': playback.motion},
                        );
                        playbackController.selectMotion('');
                      },
              ),
              const Spacer(),
              Text(
                '${Fmt.duration(playback.time)} / ${Fmt.duration(playback.duration)}',
                style: TextStyle(fontSize: 11, color: tokens.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              SmallIconButton(
                icon: playback.playing ? Icons.pause : Icons.play_arrow,
                tooltipKey: playback.playing ? 'motion.pause' : 'motion.play',
                onPressed: () {
                  final runtimeController = ref.read(runtimeProvider.notifier);
                  if (playback.playing) {
                    runtimeController.pause();
                  } else if (playback.motion != null) {
                    runtimeController.play(
                      playback.motion!,
                      loop: playback.loop,
                    );
                  }
                },
              ),
              SmallIconButton(
                icon: Icons.stop,
                tooltipKey: 'motion.stop',
                onPressed: () async {
                  await ref.read(runtimeProvider.notifier).pause();
                  playbackController.stop();
                  await ref.read(runtimeProvider.notifier).seek(0);
                },
              ),
              SmallIconButton(
                icon: Icons.skip_previous,
                tooltipKey: 'motion.prevFrame',
                onPressed: () {
                  final time = (playback.time - 1 / 24).clamp(
                    0.0,
                    playback.duration,
                  );
                  playbackController.setTime(time);
                  ref.read(runtimeProvider.notifier).seek(time);
                },
              ),
              SmallIconButton(
                icon: Icons.skip_next,
                tooltipKey: 'motion.nextFrame',
                onPressed: () {
                  final time = (playback.time + 1 / 24).clamp(
                    0.0,
                    playback.duration,
                  );
                  playbackController.setTime(time);
                  ref.read(runtimeProvider.notifier).seek(time);
                },
              ),
              SmallIconButton(
                icon: Icons.loop,
                tooltipKey: 'motion.loop',
                selected: playback.loop,
                onPressed: () => playbackController.setLoop(!playback.loop),
              ),
              SmallIconButton(
                icon: playback.recording
                    ? Icons.fiber_manual_record
                    : Icons.fiber_manual_record_outlined,
                tooltipKey: 'motion.record',
                selected: playback.recording,
                onPressed: () =>
                    playbackController.setRecording(!playback.recording),
              ),
              const Spacer(),
              SizedBox(
                width: 120,
                child: LabeledSlider(
                  label: 'motion.speed'.tr(),
                  value: playback.speed,
                  min: 0.25,
                  max: 2,
                  defaultValue: 1,
                  onChanged: playbackController.setSpeed,
                ),
              ),
              SizedBox(
                width: 150,
                child: LabeledSlider(
                  label: 'motion.duration'.tr(),
                  value: playback.duration,
                  min: 0.5,
                  max: 30,
                  digits: 1,
                  onChanged: (value) {
                    playbackController.setDuration(value);
                    if (current != null) {
                      ref.read(documentProvider.notifier).dispatch(
                        'motion.set_meta',
                        <String, Object?>{
                          'motion': '${current['name']}',
                          'duration': value,
                        },
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tracks(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> motion,
    PlaybackState playback,
  ) {
    final tokens = AppTheme.of(context);
    final curves = asJsonList(motion['curves']).map(asJsonMap).toList();
    final document = ref.read(documentProvider);
    return Column(
      children: <Widget>[
        _Ruler(playback: playback),
        Expanded(
          child: curves.isEmpty
              ? EmptyState(
                  icon: Icons.graphic_eq,
                  titleKey: 'panel.timeline.noCurve',
                  subtitleKey: 'panel.timeline.noCurveHint',
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    for (final curve in curves)
                      _TrackRow(
                        motion: '${motion['name']}',
                        curve: curve,
                        playback: playback,
                        label:
                            '${document.parameters['${curve['param']}']?['name'] ?? curve['param']}',
                        divider: tokens.divider,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Ruler extends ConsumerWidget {
  const _Ruler({required this.playback});

  final PlaybackState playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final duration = playback.duration <= 0 ? 1.0 : playback.duration;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final time = (details.localPosition.dx / width * duration).clamp(
                0.0,
                duration,
              );
              ref.read(playbackProvider.notifier).setTime(time);
              ref.read(runtimeProvider.notifier).seek(time);
            },
            onHorizontalDragUpdate: (details) {
              final time = (details.localPosition.dx / width * duration).clamp(
                0.0,
                duration,
              );
              ref.read(playbackProvider.notifier).setTime(time);
              ref.read(runtimeProvider.notifier).seek(time);
            },
            child: CustomPaint(
              painter: _RulerPainter(
                duration: duration,
                time: playback.time,
                color: tokens.textMuted,
                playhead: tokens.selectionStroke,
              ),
              size: Size(width, 22),
            ),
          );
        },
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.duration,
    required this.time,
    required this.color,
    required this.playhead,
  });

  final double duration;
  final double time;
  final Color color;
  final Color playhead;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = color
      ..strokeWidth = 1;
    final seconds = duration.ceil();
    for (var i = 0; i <= seconds; i++) {
      final x = size.width * (i / duration);
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 12), Offset(x, 22), tick);
      if (i % 5 == 0) {
        canvas.drawLine(Offset(x, 6), Offset(x, 22), tick);
      }
    }
    final head = size.width * (time / duration).clamp(0.0, 1.0);
    canvas.drawLine(
      Offset(head, 0),
      Offset(head, size.height),
      Paint()
        ..color = playhead
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.duration != duration ||
      oldDelegate.color != color;
}

class _TrackRow extends ConsumerStatefulWidget {
  const _TrackRow({
    required this.motion,
    required this.curve,
    required this.playback,
    required this.label,
    required this.divider,
  });

  final String motion;
  final Map<String, Object?> curve;
  final PlaybackState playback;
  final String label;
  final Color divider;

  @override
  ConsumerState<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends ConsumerState<_TrackRow> {
  double? _dragTime;
  double? _dragStartTime;

  @override
  Widget build(BuildContext context) {
    final param = '${widget.curve['param']}';
    final keys = asJsonList(widget.curve['keys']).map(asJsonMap).toList();
    final duration = widget.playback.duration <= 0
        ? 1.0
        : widget.playback.duration;

    return SizedBox(
      height: 22,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final time = (details.localPosition.dx / width * duration)
                        .clamp(0.0, duration);
                    ref.read(playbackProvider.notifier).setTime(time);
                    ref.read(runtimeProvider.notifier).seek(time);
                  },
                  onSecondaryTapUp: (details) {
                    final time = (details.localPosition.dx / width * duration)
                        .clamp(0.0, duration);
                    final key = _nearestKey(keys, time, duration, width);
                    if (key == null) return;
                    ref
                        .read(documentProvider.notifier)
                        .dispatch('motion.remove_key', <String, Object?>{
                          'motion': widget.motion,
                          'param': param,
                          'time': asDouble(key['time']),
                        });
                  },
                  onPanStart: (details) {
                    final time = (details.localPosition.dx / width * duration)
                        .clamp(0.0, duration);
                    final key = _nearestKey(keys, time, duration, width);
                    if (key == null) return;
                    setState(() {
                      _dragStartTime = asDouble(key['time']);
                      _dragTime = _dragStartTime;
                    });
                  },
                  onPanUpdate: (details) {
                    if (_dragStartTime == null) return;
                    final time = (details.localPosition.dx / width * duration)
                        .clamp(0.0, duration);
                    setState(() => _dragTime = time);
                  },
                  onPanEnd: (_) async {
                    final start = _dragStartTime;
                    final end = _dragTime;
                    setState(() {
                      _dragStartTime = null;
                      _dragTime = null;
                    });
                    if (start == null || end == null) return;
                    if ((start - end).abs() < 1e-4) return;
                    final key = keys.firstWhereOrNull(
                      (item) => (asDouble(item['time']) - start).abs() < 1e-6,
                    );
                    if (key == null) return;
                    final controller = ref.read(documentProvider.notifier);
                    await controller.dispatch(
                      'motion.remove_key',
                      <String, Object?>{
                        'motion': widget.motion,
                        'param': param,
                        'time': start,
                      },
                    );
                    await controller
                        .dispatch('motion.set_key', <String, Object?>{
                          'motion': widget.motion,
                          'param': param,
                          'time': end,
                          'value': asDouble(key['value']),
                          'interp': key['interp'],
                          'in_tangent': asDouble(key['in_tangent']),
                          'out_tangent': asDouble(key['out_tangent']),
                        });
                  },
                  child: CustomPaint(
                    painter: _TrackPainter(
                      keys: keys,
                      duration: duration,
                      time: widget.playback.time,
                      dragTime: _dragTime,
                      dragStartTime: _dragStartTime,
                      keyColor: Theme.of(context).colorScheme.primary,
                      divider: widget.divider,
                    ),
                    size: Size(width, 22),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Object?>? _nearestKey(
    List<Map<String, Object?>> keys,
    double time,
    double duration,
    double width,
  ) {
    Map<String, Object?>? best;
    var bestDistance = 8.0;
    for (final key in keys) {
      final x = width * (asDouble(key['time']) / duration);
      final distance = (x - width * (time / duration)).abs();
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = key;
      }
    }
    return best;
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({
    required this.keys,
    required this.duration,
    required this.time,
    required this.dragTime,
    required this.dragStartTime,
    required this.keyColor,
    required this.divider,
  });

  final List<Map<String, Object?>> keys;
  final double duration;
  final double time;
  final double? dragTime;
  final double? dragStartTime;
  final Color keyColor;
  final Color divider;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = divider
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      line,
    );

    final diamond = Paint()..color = keyColor;
    for (final key in keys) {
      final raw = asDouble(key['time']);
      final keyTime =
          (dragStartTime != null &&
              dragTime != null &&
              (raw - dragStartTime!).abs() < 1e-6)
          ? dragTime!
          : raw;
      final x = size.width * (keyTime / duration).clamp(0.0, 1.0);
      final center = Offset(x, size.height / 2);
      final path = Path()
        ..moveTo(center.dx, center.dy - 5)
        ..lineTo(center.dx + 5, center.dy)
        ..lineTo(center.dx, center.dy + 5)
        ..lineTo(center.dx - 5, center.dy)
        ..close();
      canvas.drawPath(path, diamond);
    }

    final head = size.width * (time / duration).clamp(0.0, 1.0);
    canvas.drawLine(
      Offset(head, 0),
      Offset(head, size.height),
      Paint()
        ..color = keyColor.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _TrackPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.keys != keys ||
      oldDelegate.dragTime != dragTime;
}
