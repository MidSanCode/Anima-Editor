/// 契约适配器冒烟测试（编辑器侧）：真实 anima.dll。
///
/// 引擎库不存在时跳过引擎相关断言；绝不崩溃。
library;

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
}
