/// 临时探针：验证翻译层要依赖的引擎行为。只用于诊断，跑完即删。
library;

import 'package:anima_editor/core/engine/am_types.dart';
import 'package:anima_editor/core/engine/ffi_am_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('probe: engine behaviors', () async {
    final engine = await tryCreateFfiEngine(width: 800, height: 600);
    if (engine == null) {
      // ignore: avoid_print
      print('ENGINE NOT FOUND');
      return;
    }

    Future<String> raw(String method, [Map<String, Object?>? p]) async {
      try {
        return 'ok ${await engine.call(method, p)}';
      } on Object catch (e) {
        return 'ERR $e';
      }
    }

    Future<void> cmd(String label, Map<String, Object?> c) async {
      // ignore: avoid_print
      print('$label -> ${await raw('doc.command', {'command': c})}');
    }

    await raw('project.load', {'path': r'F:\exeliang\Anima\temp\amproj-demo'});

    // 1. node_create 是否回传新 id？
    await cmd('node_create(warp)', {
      'op': 'node_create',
      'kind': 'warp_deformer',
      'name': 'W1',
      'parent': 'node-body',
      'rows': 2,
      'cols': 2,
      'rect': {
        'min': {'x': -100.0, 'y': -100.0},
        'max': {'x': 100.0, 'y': 100.0},
      },
    });

    // 2. 模型里 warp 的字段长什么样（control_points? points?）
    final model = await engine.call('doc.model');
    for (final n in asJsonList(asJsonMap(model)['nodes'])) {
      final node = asJsonMap(n);
      if ('${node['id']}' == 'W1') {
        // ignore: avoid_print
        print('warp node -> $node');
      }
    }

    // 3. uv_rect 的 Rect 形状
    await cmd('drawable_set_uv_rect', {
      'op': 'drawable_set_uv_rect',
      'node': 'node-body',
      'uv_rect': {
        'min': {'x': 0.0, 'y': 0.0},
        'max': {'x': 1.0, 'y': 1.0},
      },
    });
    // 4. masks
    await cmd('drawable_set_masks', {
      'op': 'drawable_set_masks',
      'node': 'node-body',
      'masks': <Object?>['W1'],
      'inverted': false,
    });
    // 5. 参数范围 / 删除
    await cmd('parameter_add', {
      'op': 'parameter_add',
      'id': 'P1',
      'name': 'P1',
      'min': -1.0,
      'max': 1.0,
      'default': 0.0,
      'group': 'G',
    });
    await cmd('parameter_set_range', {
      'op': 'parameter_set_range',
      'parameter': 'P1',
      'min': -2.0,
      'max': 2.0,
      'default': 0.5,
    });
    // 6. keyform_record 用真实参数
    await cmd('keyform_record', {
      'op': 'keyform_record',
      'node': 'node-body',
      'parameter': 'P1',
      'value': 1.0,
      'vertices': <Object?>[
        {'x': -1.0, 'y': -1.0},
      ],
      'opacity': 0.5,
    });
    await cmd('keyform_remove', {
      'op': 'keyform_remove',
      'node': 'node-body',
      'parameter': 'P1',
      'value': 1.0,
    });
    await cmd('parameter_remove', {'op': 'parameter_remove', 'parameter': 'P1'});
    // 7. batch
    await cmd('batch', {
      'op': 'batch',
      'commands': <Object?>[
        {
          'op': 'node_rename',
          'node': 'node-body',
          'name': 'Body2',
        },
      ],
      'label': 'probe',
    });
    // 8. node_set_rotation
    await cmd('node_set_rotation', {
      'op': 'node_set_rotation',
      'node': 'node-body',
      'angle': 12.0,
    });
    // 9. config.extra 是否原样保留？
    final spec = await engine.call('project.spec');
    final config = asJsonMap(spec['config']);
    config['probe_extra'] = <String, Object?>{'length': 20.0};
    // ignore: avoid_print
    print('set_spec extra -> ${await raw('project.set_spec', {'spec': spec})}');
    final back = asJsonMap((await engine.call('project.spec'))['config']);
    // ignore: avoid_print
    print('config extra survived -> ${back['probe_extra']}');

    // 10. 最终模型快照
    final m2 = await engine.call('doc.model');
    // ignore: avoid_print
    print('nodes after -> ${asJsonList(asJsonMap(m2)['nodes']).map((e) => asJsonMap(e)['id']).toList()}');
    // ignore: avoid_print
    print('params after -> ${asJsonList(asJsonMap(m2)['parameters']).map((e) => asJsonMap(e)['id']).toList()}');

    await engine.dispose();
  });
}