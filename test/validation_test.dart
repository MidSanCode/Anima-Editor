/// 校验与安全测试：资源哈希、名称规则、zip-slip 防护、导入回滚。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anima_editor/core/engine/am_types.dart';
import 'package:anima_editor/core/engine/local_am_engine.dart';
import 'package:anima_editor/core/project/amproj_reader.dart';
import 'package:anima_editor/core/project/amproj_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LocalAmEngine engine;

  String path(String name) => '${temp.path}${Platform.pathSeparator}$name';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anima_validate_');
    engine = LocalAmEngine();
    await engine.initialize(width: 256, height: 256, devicePixelRatio: 1);
  });

  tearDown(() async {
    await engine.dispose();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  test('资源字节被篡改后校验报告 HASH_MISMATCH', () async {
    final dir = path('assets_project');
    await engine.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'assets_project',
    });

    await AmprojWriter.writeAsset(
      dir,
      'assets/images/tex.png',
      Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
    );

    var report = await engine.call('project.validate');
    expect(report['ok'], isTrue, reason: '${report['issues']}');

    // 篡改内容但不更新 metadata 里的哈希。
    File(
      '$dir${Platform.pathSeparator}assets${Platform.pathSeparator}images'
      '${Platform.pathSeparator}tex.png',
    ).writeAsBytesSync(<int>[9, 9, 9, 9, 9, 9, 9, 9]);

    report = await engine.call('project.validate');
    expect(report['ok'], isFalse);
    final codes = asJsonList(
      report['issues'],
    ).map((e) => '${asJsonMap(e)['code']}').toList();
    expect(codes, contains('HASH_MISMATCH'));
  });

  test('非法工程名被拒绝', () async {
    await expectLater(
      engine.call('project.create', <String, Object?>{
        'dir': path('bad_name'),
        'name': 'Bad Name',
      }),
      throwsA(isA<AmException>().having((e) => e.code, 'code', 'NAME_INVALID')),
    );
  });

  test('压缩包内的目录穿越条目被拒绝（zip-slip）', () async {
    final entries = <String, Uint8List>{
      '../evil.json': Uint8List.fromList(<int>[123, 125]),
    };
    final bytes = encodeAmprojArchive(entries);
    expect(
      () => decodeAmprojArchive(bytes),
      throwsA(isA<AmException>().having((e) => e.code, 'code', 'ZIP_SLIP')),
    );
  });

  test('导入到非空目录被拒绝且不产生副作用', () async {
    final dir = path('src');
    await engine.call('project.create', <String, Object?>{
      'dir': dir,
      'name': 'src',
    });
    final exported = await engine.call('project.export');
    final archive = '${exported['path']}';

    final dest = path('occupied');
    Directory(dest).createSync(recursive: true);
    File('$dest${Platform.pathSeparator}keep.txt').writeAsStringSync('keep');

    await expectLater(
      engine.call('project.import', <String, Object?>{
        'source': archive,
        'dest': dest,
      }),
      throwsA(
        isA<AmException>().having((e) => e.code, 'code', 'DEST_NOT_EMPTY'),
      ),
    );
    expect(File('$dest${Platform.pathSeparator}keep.txt').existsSync(), isTrue);
  });

  test('导入损坏的压缩包会回滚目标目录', () async {
    final broken = path('broken.amproj');
    // 合法 zip 结构但缺少 info.json / registry.json。
    final bytes = encodeAmprojArchive(<String, Uint8List>{
      'assets/note.txt': Uint8List.fromList(<int>[104, 105]),
    });
    File(broken).writeAsBytesSync(bytes);

    final dest = path('rollback_target');
    await expectLater(
      engine.call('project.import', <String, Object?>{
        'source': broken,
        'dest': dest,
      }),
      throwsA(isA<AmException>()),
    );
    final leftovers = Directory(dest).existsSync()
        ? Directory(dest).listSync()
        : const <FileSystemEntity>[];
    expect(leftovers, isEmpty);
  });
}
