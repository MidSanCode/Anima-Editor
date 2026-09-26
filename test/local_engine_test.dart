/// 内置引擎（降级实现）的行为测试：命令、撤销重做、求值、动作、统计。
library;

import 'package:anima_editor/core/engine/am_types.dart';
import 'package:anima_editor/core/engine/local_am_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalAmEngine engine;

  setUp(() async {
    engine = LocalAmEngine(demo: true);
    await engine.initialize(width: 512, height: 512, devicePixelRatio: 1);
  });

  tearDown(() async {
    await engine.dispose();
  });

  test('降级引擎声明核心契约方法且不提供纹理桥', () {
    expect(engine.isAvailable, isTrue);
    expect(engine.backend.id, 'local');
    for (final method in <String>[
      'doc.command',
      'doc.undo',
      'doc.redo',
      'doc.query',
      'project.create',
      'project.open',
      'project.save',
      'project.validate',
      'project.export',
      'project.import',
      'runtime.set_param',
      'runtime.seek',
      'renderer.pick',
      'diagnostics.stats',
    ]) {
      expect(
        engine.capabilities.supports(method),
        isTrue,
        reason: 'missing $method',
      );
    }
    expect(engine.textureInfo, isNull);
  });

  test('doc.command 递增修订号，撤销重做可恢复', () async {
    final before = await engine.call('doc.revision');
    final revision0 = before['revision']! as int;

    final created = await engine.call('doc.command', <String, Object?>{
      'command': <String, Object?>{
        'op': 'node.create',
        'kind': 'drawable',
        'name': 'TestLayer',
      },
    });
    final revision1 = created['revision']! as int;
    expect(revision1, greaterThan(revision0));

    final hierarchy = await engine.call('doc.query', <String, Object?>{
      'path': 'hierarchy',
    });
    final nodes = asJsonMap(hierarchy['nodes']);
    expect(
      nodes.values.map((e) => '${asJsonMap(e)['name']}'),
      contains('TestLayer'),
    );

    final undone = await engine.call('doc.undo');
    expect(undone['revision'], isNot(revision1));
    final afterUndo = asJsonMap(
      (await engine.call('doc.query', <String, Object?>{
        'path': 'hierarchy',
      }))['nodes'],
    );
    expect(
      afterUndo.values.map((e) => '${asJsonMap(e)['name']}'),
      isNot(contains('TestLayer')),
    );

    await engine.call('doc.redo');
    final afterRedo = asJsonMap(
      (await engine.call('doc.query', <String, Object?>{
        'path': 'hierarchy',
      }))['nodes'],
    );
    expect(
      afterRedo.values.map((e) => '${asJsonMap(e)['name']}'),
      contains('TestLayer'),
    );
  });

  test('未知命令抛出 AmException 而不是崩溃', () async {
    await expectLater(
      engine.call('doc.command', <String, Object?>{
        'command': <String, Object?>{'op': 'nope.not_a_command'},
      }),
      throwsA(isA<AmException>()),
    );
  });

  test('参数求值影响关键形结果（角度驱动旋转变形器）', () async {
    Future<String> signature() async {
      final scene = await engine.call('doc.query', <String, Object?>{
        'path': 'scene',
      });
      final buffer = StringBuffer();
      for (final raw in asJsonList(scene['drawables'])) {
        final drawable = asJsonMap(raw);
        for (final vertex in asJsonList(drawable['vertices'])) {
          final pair = asJsonList(vertex);
          buffer.write('${asDouble(pair[0]).toStringAsFixed(4)},');
          buffer.write('${asDouble(pair[1]).toStringAsFixed(4)};');
        }
      }
      return buffer.toString();
    }

    final params = await engine.call('doc.query', <String, Object?>{
      'path': 'parameters',
    });
    final angleX = asJsonMap(params['parameters']).entries
        .map((e) => asJsonMap(e.value))
        .firstWhere((p) => '${p['name']}' == 'AngleX');
    final angleXId = '${angleX['id']}';
    expect(angleXId, isNotEmpty);

    final neutral = await signature();
    expect(neutral, isNotEmpty);

    // 以 id 赋值（契约主路径）。
    await engine.call('runtime.set_param', <String, Object?>{
      'param': angleXId,
      'value': 30,
    });
    final turned = await signature();
    expect(turned, isNot(neutral));

    // 以参数名赋值（别名）必须等价。
    await engine.call('runtime.set_param', <String, Object?>{
      'param': angleXId,
      'value': 0,
    });
    expect(await signature(), neutral);
    await engine.call('runtime.set_param', <String, Object?>{
      'param': 'AngleX',
      'value': 30,
    });
    expect(await signature(), turned);
  });

  test('动作播放推进时间并写入参数', () async {
    final motions = await engine.call('doc.query', <String, Object?>{
      'path': 'motions',
    });
    final list = asJsonList(motions['motions']);
    expect(list, isNotEmpty);
    final name = '${asJsonMap(list.first)['name']}';

    final played = await engine.call('runtime.play_motion', <String, Object?>{
      'motion': name,
    });
    expect(played['motion'], name);

    final seeked = await engine.call('runtime.seek', <String, Object?>{
      'time': 0.5,
    });
    expect(asDouble(seeked['time']), closeTo(0.5, 0.0001));

    await engine.call('runtime.stop_motion');
    final params = await engine.call('runtime.params');
    expect(asJsonMap(params['params']), isNotEmpty);
  });

  test('诊断统计返回结构计数', () async {
    final stats = await engine.call('diagnostics.stats');
    expect(asInt(stats['nodes']), greaterThan(0));
    expect(asInt(stats['drawables']), greaterThan(0));
    expect(asInt(stats['parameters']), greaterThan(0));
    expect(stats['fallback'], isTrue);
  });

  test('命中测试返回节点 id', () async {
    final picked = await engine.call('renderer.pick', <String, Object?>{
      'x': 0.0,
      'y': 0.0,
    });
    expect(picked.containsKey('id'), isTrue);
  });
}
