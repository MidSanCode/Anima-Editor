/// `.amproj` 目录工程与压缩包的往返测试（创建 / 保存 / 校验 / 导出 / 导入）。
library;

import 'dart:io';

import 'package:anima_editor/core/engine/am_types.dart';
import 'package:anima_editor/core/engine/local_am_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LocalAmEngine engine;

  String path(String name) => '${temp.path}${Platform.pathSeparator}$name';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anima_roundtrip_');
    engine = LocalAmEngine(demo: true);
    await engine.initialize(width: 512, height: 512, devicePixelRatio: 1);
  });

  tearDown(() async {
    await engine.dispose();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  test('创建目录工程时写出格式规定的骨架文件', () async {
    final dir = path('demo');
    final created = await engine.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'demo',
      'display_name': 'Demo Model',
      'author': 'tester',
    });

    expect(created['name'], 'demo');
    expect(File('$dir${Platform.pathSeparator}info.json').existsSync(), isTrue);
    expect(
      File('$dir${Platform.pathSeparator}registry.json').existsSync(),
      isTrue,
    );
    expect(
      Directory('$dir${Platform.pathSeparator}metadata').existsSync(),
      isTrue,
    );
    expect(
      Directory('$dir${Platform.pathSeparator}assets').existsSync(),
      isTrue,
    );
  });

  test('编辑 → 保存 → 校验 → 导出 → 导入 完整往返', () async {
    final dir = path('roundtrip');
    await engine.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'roundtrip',
    });

    await engine.call('doc.command', <String, Object?>{
      'command': <String, Object?>{
        'op': 'node.create',
        'kind': 'drawable',
        'name': 'RoundTripLayer',
      },
    });

    final saved = await engine.call('project.save');
    expect(saved['path'], isNotNull);

    final report = await engine.call('project.validate');
    expect(report['ok'], isTrue, reason: '${report['issues']}');

    final exported = await engine.call('project.export');
    final archive = '${exported['path']}';
    expect(File(archive).existsSync(), isTrue);
    expect(archive.endsWith('.amproj'), isTrue);
    expect(File('$archive.sha256').existsSync(), isTrue);
    final sha = '${exported['sha256']}';
    expect(sha.length, 64);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sha), isTrue);

    final dest = path('imported');
    final imported = await engine.call('project.import', <String, Object?>{
      'source': archive,
      'dest': dest,
    });
    expect('${imported['path']}'.isNotEmpty, isTrue);

    final hierarchy = await engine.call('doc.query', <String, Object?>{
      'path': 'hierarchy',
    });
    final names = asJsonMap(
      hierarchy['nodes'],
    ).values.map((e) => '${asJsonMap(e)['name']}').toList();
    expect(names, contains('RoundTripLayer'));

    // 导入结果自身也必须通过校验。
    final revalidate = await engine.call('project.validate');
    expect(revalidate['ok'], isTrue, reason: '${revalidate['issues']}');
  });

  test('导出前校验失败时拒绝产出压缩包', () async {
    final dir = path('broken');
    await engine.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'broken',
    });
    // 人为破坏 info.json 的名称字段。
    final infoPath = '$dir${Platform.pathSeparator}info.json';
    final info = File(infoPath).readAsStringSync();
    File(
      infoPath,
    ).writeAsStringSync(info.replaceAll('"broken"', '"Broken Name"'));

    final report = await engine.call('project.validate');
    expect(report['ok'], isFalse);
    final codes = asJsonList(
      report['issues'],
    ).map((e) => '${asJsonMap(e)['code']}').toList();
    expect(codes, contains('NAME_INVALID'));

    await expectLater(
      engine.call('project.export'),
      throwsA(isA<AmException>()),
    );
  });
}
