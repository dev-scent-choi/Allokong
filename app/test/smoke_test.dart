import 'dart:convert';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('내장 도안 에셋이 실려 있고 dohan_core 로 읽힌다', () async {
    final metaBytes = await rootBundle.load('assets/dohans/flower-01/meta.json');
    final meta = DohanMeta.parse(
      utf8.decode(metaBytes.buffer.asUint8List()),
      label: 'assets/dohans/flower-01',
    );

    expect(meta.id, 'flower-01');
    expect(meta.canvasSize, [1024, 1024]);
    expect(meta.regionCount, greaterThanOrEqualTo(4));
  });
}
