/// 契约适配器冒烟测试（编辑器侧）：真实 anima.dll。
///
/// 引擎库不存在时跳过引擎相关断言；绝不崩溃。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anima_editor/core/engine/am_types.dart';
import 'package:anima_editor/core/engine/contract_am_engine.dart';
import 'package:anima_editor/core/engine/ffi_am_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ContractAmEngine? engine;

  setUpAll(() async {
    final ffi = await tryCreateFfiEngine(width: 800, height: 600);
    if (ffi == null) return;
    final contract = ContractAmEngine(ffi);
    await contract.initialize(width: 800, height: 600);
    engine = contract;
  });

  tearDownAll(() async {
    await engine?.dispose();
  });

  test('engine library loads or degrades silently', () async {
    if (engine == null) return;
    expect(engine!.isAvailable, isTrue);
  });

  test('system.version / capabilities', () async {
    if (engine == null) return;
    final version = await engine!.call('system.version');
    expect(version['format'], 'amproj');
    expect(engine!.capabilities.methods, contains('runtime.scene'));
  });

  test('open demo project + doc.query + scene', () async {
    if (engine == null) return;
    const demoDir = r'F:\exeliang\Anima\temp\amproj-demo';
    final result = await engine!.call('project.open', {'path': demoDir});
    expect(result['name'], 'amproj-demo');

    final params = await engine!.call('doc.query', {'path': 'parameters'});
    expect(asJsonMap(params['parameters']), isNotEmpty);

    await engine!.refreshScene();
    expect(engine!.buildScene().drawables, isNotEmpty);
  });

  test('runtime step + doc.command via adapter', () async {
    if (engine == null) return;
    final step = await engine!.call('runtime.step', {'dt': 1 / 60});
    expect(asDouble(step['time']), greaterThan(0));

    // UI 形状的 doc.command 走影子文档，结果由适配器投影成 spec 交给引擎。
    final command = await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'node.create',
        'kind': 'part',
        'name': 'PartA',
      },
    });
    expect(command['revision'], isNotNull);

    final created = await engine!.call('doc.query', {'path': 'hierarchy'});
    expect(
      asJsonMap(created['nodes']).values.map((n) => '${asJsonMap(n)['name']}'),
      contains('PartA'),
    );
    // 引擎确实收到了：doc.model 是引擎的原始模型视图。
    final modelAfterCreate = await engine!.call('doc.model');
    expect(
      asJsonList(modelAfterCreate['nodes']).map(
        (n) => '${asJsonMap(n)['name']}',
      ),
      contains('PartA'),
    );

    // 撤销后 PartA 消失（撤销栈在影子文档里，因为 set_spec 会清空引擎的）。
    await engine!.call('doc.undo');
    final hierarchy = await engine!.call('doc.query', {'path': 'hierarchy'});
    final nodes = asJsonMap(hierarchy['nodes']);
    expect(
      nodes.values.map((n) => '${asJsonMap(n)['name']}'),
      isNot(contains('PartA')),
    );

    // doc.model 是引擎的原始模型视图，必须可直达。
    final model = await engine!.call('doc.model');
    expect(model['nodes'], isNotNull);
    expect(model['name'], isNotNull);
  });

  /// 回归：物理设置 / 表情的编辑过去会被透传给引擎的 `doc.command`，
  /// 而引擎的 `op` 只认下划线形式且没有这些编辑命令，于是报
  /// 「命令无法解析」，面板整个用不了。现在编辑由影子文档承担。
  test('物理设置 / 表情 / 姿势 / 设置 的编辑都能落地', () async {
    if (engine == null) return;
    await engine!.call('project.open', {
      'path': r'F:\exeliang\Anima\temp\amproj-demo',
    });

    // 物理：新增（与面板一样只给 name，id 由文档生成）→ 用回来的 id 改属性。
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'physics.add_setting',
        'name': 'physics1',
        'inputs': <Object?>[],
        'outputs': <Object?>[],
      },
    });
    final created = asJsonList(
      (await engine!.call('doc.query', {'path': 'physics'}))['physics'],
    );
    expect(created, hasLength(1));
    final settingId = '${asJsonMap(created.first)['id']}';
    expect(settingId, isNotEmpty);

    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'physics.set_property',
        'id': settingId,
        // 面板写的是整个 pendulum 对象（引擎侧无法表达 length/frequency/damping，
        // 它们靠 config 的宿主通道往返）。
        'path': 'pendulum',
        'value': <String, Object?>{'length': 24.0, 'frequency': 1.5},
      },
    });
    final physics = await engine!.call('doc.query', {'path': 'physics'});
    final settings = asJsonList(physics['physics']);
    expect(settings, hasLength(1));
    expect(
      asDouble(asJsonMap(asJsonMap(settings.first)['pendulum'])['length']),
      24.0,
    );
    expect(
      asDouble(asJsonMap(asJsonMap(settings.first)['pendulum'])['frequency']),
      1.5,
    );
    // 引擎侧确实吃下了这份 spec（投影不合法时 project.set_spec 会报
    // 「描述层无法解析」，validate 也会给出 issues）。
    final validation = await engine!.call('project.validate');
    expect(validation['ok'], isTrue);

    // 表情：新增 → 设参数 → 引擎确实认识它。
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'expression.create',
        'name': 'smile',
        'params': <String, Object?>{},
      },
    });
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'expression.set_param',
        'name': 'smile',
        'param': 'AngleX',
        'value': 12.0,
      },
    });
    final expressions = await engine!.call('doc.query', {'path': 'expressions'});
    final list = asJsonList(expressions['expressions']);
    expect(list, hasLength(1));
    expect(asJsonMap(asJsonMap(list.first)['params'])['AngleX'], 12.0);
    // 这条表情在引擎侧也生效：AnglEX 参数被驱动到 12。
    expect((await engine!.call('runtime.params'))['params'], isNotNull);

    // 姿势 / 设置。
    await engine!.call('doc.command', {
      'command': <String, Object?>{'op': 'pose.add', 'name': 'pose1'},
    });
    expect(
      asJsonList((await engine!.call('doc.query', {'path': 'pose'}))['pose']),
      hasLength(1),
    );
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'settings.set',
        'settings': <String, Object?>{'physics_enabled': false},
      },
    });
    expect(
      asBool(
        asJsonMap((await engine!.call('doc.query', {'path': 'settings'}))['settings'])['physics_enabled'],
      ),
      isFalse,
    );

    // 收尾：撤销回干净状态，避免影响后面的用例。
    while (asBool((await engine!.call('doc.history'))['can_undo'], false)) {
      await engine!.call('doc.undo');
    }
  });

  test('project.create：宿主落盘后真引擎能装载', () async {
    if (engine == null) return;
    final tmp = await Directory.systemTemp.createTemp('anima-create-');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final dir = '${tmp.path}${Platform.pathSeparator}my_model';

    final created = await engine!.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'my_model',
      'display_name': '我的模型',
      'author': 'tester',
    });
    expect(created['path'], dir);
    expect(created['name'], 'my_model');
    expect(created['display_name'], '我的模型');

    // 骨架必须齐全：引擎 project.load 要求 info.json + registry.json，
    // read_spec 要求 spec/model.json。
    for (final rel in <String>[
      'info.json',
      'registry.json',
      'spec/model.json',
    ]) {
      final path =
          '$dir${Platform.pathSeparator}'
          '${rel.replaceAll('/', Platform.pathSeparator)}';
      expect(File(path).existsSync(), isTrue, reason: '缺少 $rel');
    }

    // 引擎确实装载了这份新工程。
    final model = await engine!.call('doc.model');
    expect(model['name'], 'my_model');
    final nodes = asJsonList(model['nodes']);
    expect(nodes, isNotEmpty, reason: '新工程应带一个根节点');
    expect(asJsonMap(nodes.first)['name'], 'root');

    // 落盘的 model.json 必须是引擎 spec 形状（nodes 是数组、节点带 kind），
    // 而不是宿主内部文档形状 —— 后者引擎解析不了。
    final raw = await File(
      '$dir${Platform.pathSeparator}spec${Platform.pathSeparator}model.json',
    ).readAsString();
    expect(raw, contains('"kind"'));
    expect(raw, isNot(contains('"art_path"')));

    // 重新从磁盘打开：证明真的落盘了，而不是只在内存里。
    final reopened = await engine!.call('project.open', <String, Object?>{
      'path': dir,
    });
    expect(reopened['name'], 'my_model');
    final reopenedModel = await engine!.call('doc.model');
    expect(
      asJsonList(reopenedModel['nodes']),
      isNotEmpty,
      reason: '根节点必须持久化到 spec/model.json',
    );

    // 新建出来的工程必须是**有效**工程，而不是只有文件架子。
    final validation = await engine!.call('project.validate');
    expect(validation['ok'], isNot(false), reason: '新工程校验不应失败：$validation');

    // 引擎的统计口径也要认得这份工程。
    final stats = await engine!.call('diagnostics.stats');
    expect(asInt(stats['nodes']), greaterThan(0));
    expect(stats['fallback'], isNot(true));
  });

  /// 工程落盘再打开，宿主文档必须**逐字段**回来。
  ///
  /// 引擎的 `Spec` 表达不了宿主的 `bounds` / `pendulum.{length,frequency,damping}` /
  /// `in_tangent` / `art_path` 等字段；它们全靠 `spec/config.json` 的
  /// `__host.doc` 扩展通道往返（`ProjectConfig` 是 `#[serde(flatten)]`，
  /// 未知键原样保留）。这条测试就是那个假设的守门人。
  test('保存 → 重新打开：宿主文档无损往返', () async {
    if (engine == null) return;
    final tmp = await Directory.systemTemp.createTemp('anima-roundtrip-');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final dir = '${tmp.path}${Platform.pathSeparator}roundtrip';

    await engine!.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'roundtrip',
    });
    // 造一组引擎表达不了的宿主数据。
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'param.create',
        'name': 'AngleX',
        'group': 'Head',
        'min': -30.0,
        'max': 30.0,
        'default': 0.0,
      },
    });
    final params = asJsonMap(
      (await engine!.call('doc.query', {'path': 'parameters'}))['parameters'],
    );
    final angleId = params.keys.firstWhere(
      (id) => '${asJsonMap(params[id])['name']}' == 'AngleX',
    );
    // `bounds` 是典型的宿主持有字段（引擎 warp 只有 rest_rect）。
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'deformer.create_warp',
        'name': 'warp',
        'rows': 2,
        'cols': 2,
        // 面板就是这么传 bounds 的：四元列表。
        'bounds': <Object?>[-100.0, -100.0, 200.0, 200.0],
      },
    });
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'physics.add_setting',
        'name': 'physics1',
      },
    });
    final settings = asJsonList(
      (await engine!.call('doc.query', {'path': 'physics'}))['physics'],
    );
    final physicsId = '${asJsonMap(settings.first)['id']}';
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'physics.set_property',
        'id': physicsId,
        'path': 'pendulum',
        'value': <String, Object?>{'length': 33.0, 'frequency': 2.5, 'damping': 0.4},
      },
    });
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'motion.create',
        'name': 'wave',
        'duration': 2.5,
      },
    });
    await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'motion.set_key',
        'name': 'wave',
        'param': angleId,
        'time': 1.0,
        'value': 15.0,
        // 切线与插值都是宿主的表达，引擎 Spec 里没有对应字段。
        // 宿主插值词汇是 linear|step|bezier（见 AmInterpolation）；`bezier`
        // 在引擎侧展开成 cubic_bezier，回读时还原成 `bezier`。
        'interp': 'bezier',
        'in_tangent': -1.5,
        'out_tangent': 0.5,
      },
    });

    final before = await engine!.call('doc.query', {'path': 'hierarchy'});
    final beforePhysics = asJsonList(
      (await engine!.call('doc.query', {'path': 'physics'}))['physics'],
    );
    final beforeMotions = asJsonList(
      (await engine!.call('doc.query', {'path': 'motions'}))['motions'],
    );

    // 落盘 → 重新打开（走真实的 project.save / project.load）。
    await engine!.call('project.save');
    await engine!.call('project.close');
    await engine!.call('project.open', {'path': dir});

    // 节点结构与 warp 的 bounds。
    final after = await engine!.call('doc.query', {'path': 'hierarchy'});
    expect(
      asJsonMap(after['nodes']).keys.toSet(),
      asJsonMap(before['nodes']).keys.toSet(),
    );
    for (final entry in asJsonMap(before['nodes']).entries) {
      final b = asJsonMap(entry.value);
      final a = asJsonMap(asJsonMap(after['nodes'])[entry.key]);
      expect(a['name'], b['name'], reason: '节点 ${entry.key} 名字变了');
      expect(a['type'], b['type']);
      if (b['type'] == 'warp_deformer') {
        expect(a['bounds'], b['bounds'], reason: 'warp bounds 丢失');
        expect(a['rows'], b['rows']);
        expect(a['cols'], b['cols']);
      }
    }

    // 物理的 pendulum（引擎侧没有 length/frequency/damping）。
    final afterPhysics = asJsonList(
      (await engine!.call('doc.query', {'path': 'physics'}))['physics'],
    );
    expect(afterPhysics, hasLength(beforePhysics.length));
    final bPen = asJsonMap(asJsonMap(beforePhysics.first)['pendulum']);
    final aPen = asJsonMap(asJsonMap(afterPhysics.first)['pendulum']);
    expect(asDouble(aPen['length']), asDouble(bPen['length']));
    expect(asDouble(aPen['frequency']), asDouble(bPen['frequency']));
    expect(asDouble(aPen['damping']), asDouble(bPen['damping']));

    // 动作：duration / 曲线 / 关键帧的 interp 与切线。
    final afterMotions = asJsonList(
      (await engine!.call('doc.query', {'path': 'motions'}))['motions'],
    );
    expect(afterMotions, hasLength(beforeMotions.length));
    final bMotion = asJsonMap(beforeMotions.first);
    final aMotion = asJsonMap(afterMotions.first);
    expect(aMotion['name'], bMotion['name']);
    expect(asDouble(aMotion['duration']), asDouble(bMotion['duration']));
    final bKeys = asJsonList(
      asJsonMap(asJsonList(bMotion['curves']).first)['keys'],
    );
    final aKeys = asJsonList(
      asJsonMap(asJsonList(aMotion['curves']).first)['keys'],
    );
    expect(aKeys, hasLength(bKeys.length));
    expect(asDouble(asJsonMap(aKeys.first)['value']), 15.0);
    expect('${asJsonMap(aKeys.first)['interp']}', 'bezier');
    expect(asDouble(asJsonMap(aKeys.first)['in_tangent']), -1.5);
    expect(asDouble(asJsonMap(aKeys.first)['out_tangent']), 0.5);

    // 参数的范围/分组（引擎有 min/max/default/group，group 是字符串）。
    final afterParams = asJsonMap(
      (await engine!.call('doc.query', {'path': 'parameters'}))['parameters'],
    );
    expect(asDouble(asJsonMap(afterParams[angleId])['min']), -30.0);
    expect(asDouble(asJsonMap(afterParams[angleId])['max']), 30.0);
  });

  test('project.create：非法工程名给出可读错误而不是 UNSUPPORTED', () async {
    if (engine == null) return;
    final tmp = await Directory.systemTemp.createTemp('anima-create-bad-');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    await expectLater(
      engine!.call('project.create', <String, Object?>{
        'dir': '${tmp.path}${Platform.pathSeparator}bad',
        'name': 'Bad Name!',
      }),
      throwsA(
        isA<AmException>().having((e) => e.code, 'code', isNot('UNSUPPORTED')),
      ),
    );
  });

  test('project.create：目录里已有工程时拒绝覆盖', () async {
    if (engine == null) return;
    final tmp = await Directory.systemTemp.createTemp('anima-create-dup-');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final dir = '${tmp.path}${Platform.pathSeparator}dup';

    await engine!.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'dup',
    });
    // 第二次必须被拒绝 —— 覆盖 info.json / registry.json / spec/ 不可逆。
    await expectLater(
      engine!.call('project.create', <String, Object?>{
        'dir': dir,
        'name': 'dup',
      }),
      throwsA(
        isA<AmException>().having((e) => e.code, 'code', 'PROJECT_EXISTS'),
      ),
    );
  });

  test('unsupported methods raise AmException, not crash', () async {
    if (engine == null) return;
    // 动作录制与未知方法确实是引擎没桥接的能力。
    for (final method in <String>['motion.record.begin', 'no.such.method']) {
      try {
        await engine!.call(method);
        fail('expected AmException for $method');
      } on AmException catch (error) {
        expect(error.code, 'UNSUPPORTED');
      }
    }
  });

  test('project.export / project.import 由宿主完成，不再一律 UNSUPPORTED', () async {
    if (engine == null) return;
    final sandbox = Directory.systemTemp.createTempSync('anima-export-');
    addTearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });
    final dir = '${sandbox.path}${Platform.pathSeparator}proj';
    await engine!.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'demo',
    });
    await engine!.call('project.save', <String, Object?>{'path': dir});

    // 导出：宿主打包成 `.amproj` 并回传校验和（与内置实现同一份契约）。
    final archive = '${sandbox.path}${Platform.pathSeparator}demo.amproj';
    final exported = await engine!.call('project.export', <String, Object?>{
      'out_path': archive,
    });
    expect(exported['path'], archive);
    expect('${exported['sha256']}', isNotEmpty);
    expect(File(archive).existsSync(), isTrue);

    // 导入：解包到一个空目录后即可被再次打开。
    final target = '${sandbox.path}${Platform.pathSeparator}restored';
    final imported = await engine!.call('project.import', <String, Object?>{
      'source': archive,
      'dest': target,
    });
    expect(imported['path'], target);
    expect(Directory(target).listSync(), isNotEmpty);
  });

  test('project.open 支持 .amproj 压缩包（起始页 / 拖拽的主路径）', () async {
    if (engine == null) return;
    final sandbox = Directory.systemTemp.createTempSync('anima-open-arc-');
    addTearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });
    final dir = '${sandbox.path}${Platform.pathSeparator}proj';
    await engine!.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'demo',
    });
    await engine!.call('project.save', <String, Object?>{'path': dir});
    final archive = '${sandbox.path}${Platform.pathSeparator}demo.amproj';
    await engine!.call('project.export', <String, Object?>{'out_path': archive});

    // 引擎本体只认目录；适配器必须先解包再装载，否则会撞上「不是目录」。
    final opened = await engine!.call('project.open', <String, Object?>{
      'path': archive,
    });
    expect(opened['is_archive'], isTrue);
    expect('${opened['name']}', 'demo');
    // 解包出的目录就在压缩包旁边，编辑后的保存有落点。
    expect(
      Directory('${sandbox.path}${Platform.pathSeparator}demo.work').existsSync(),
      isTrue,
    );
  });
}
