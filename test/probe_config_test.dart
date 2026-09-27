/// 临时探针：确认 `config.extra` 能否作为宿主专有字段的持久化通道。
/// 只用于诊断，跑完即删。
library;

import 'package:anima_editor/core/engine/am_types.dart';
import 'package:anima_editor/core/engine/ffi_am_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('probe: config.extra round trip', () async {
    final engine = await tryCreateFfiEngine(width: 800, height: 600);
    if (engine == null) {
      // ignore: avoid_print
      print('ENGINE NOT FOUND');
      return;
    }

    Future<String> raw(String m, [Map<String, Object?>? p]) async {
      try {
        return 'ok ${await engine.call(m, p)}';
      } on Object catch (e) {
        return 'ERR $e';
      }
    }

    await raw('project.load', {'path': r'F:\exeliang\Anima\temp\amproj-demo'});
    final spec = await engine.call('project.spec');
    // ignore: avoid_print
    print('config before -> ${spec['config']}');

    final config = asJsonMap(spec['config']);
    config['host_physics'] = <String, Object?>{
      'ps1': <String, Object?>{'length': 20.0, 'frequency': 1.2, 'damping': 0.3},
    };
    final spec2 = <String, Object?>{...spec, 'config': config};
    // ignore: avoid_print
    print('set_spec -> ${await raw('project.set_spec', {'spec': spec2})}');
    final back = await engine.call('project.spec');
    // ignore: avoid_print
    print('config after -> ${back['config']}');

    // 顺带确认：物理设置里塞未知字段会被 serde 丢弃。
    final s3 = await engine.call('project.spec');
    final ph = asJsonMap(s3['physics']);
    ph['settings'] = <Object?>[
      <String, Object?>{
        'id': 'ps1',
        'name': 'ps1',
        'kind': 'pendulum',
        'inputs': <Object?>[],
        'outputs': <Object?>[],
        'vertices': <Object?>[],
        'length': 20.0,
        'frequency': 1.2,
        'damping': 0.3,
      },
    ];
    // ignore: avoid_print
    print(
      'set_spec(physics unknown) -> '
      '${await raw('project.set_spec', {'spec': <String, Object?>{...s3, 'physics': ph}})}',
    );
    final b3 = await engine.call('project.spec');
    // ignore: avoid_print
    print('physics after -> ${asJsonMap(b3['physics'])['settings']}');

    await engine.dispose();
  });
}