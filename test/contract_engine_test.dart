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

    // UI 形状的 doc.command 直接透传给引擎。
    final command = await engine!.call('doc.command', {
      'command': <String, Object?>{
        'op': 'node_create',
        'kind': 'part',
        'name': 'PartA',
      },
    });
    expect(command['revision'], isNotNull);

    // 撤销后 PartA 消失。
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
    expect(asJsonMap(nodes.first)['name'], 'Root');

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
}
