import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/paintable_mask.dart';

Future<List<int>> _alphaRow(ui.Image img) async {
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return [
    for (var x = 0; x < img.width; x++) bytes.getUint8(x * 4 + 3),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('칠할 수 있는 픽셀만 불투명하다', () async {
    // 0 = 선, 1 = 배경, 2·3 = 칠할 수 있는 영역
    final ids = Uint16List.fromList([0, 1, 2, 3, 0]);
    final mask = await buildPaintableMask(RegionMap(5, 1, ids));

    expect(await _alphaRow(mask), [0, 0, 255, 255, 0]);
  });

  test('크기가 인덱스맵과 같다', () async {
    final mask = await buildPaintableMask(
      RegionMap(7, 3, Uint16List(21)..fillRange(0, 21, 2)),
    );
    expect(mask.width, 7);
    expect(mask.height, 3);
  });

  test('16bit 영역 ID 도 칠할 수 있는 것으로 친다', () async {
    final ids = Uint16List.fromList([1, 300, 65535]);
    final mask = await buildPaintableMask(RegionMap(3, 1, ids));
    expect(await _alphaRow(mask), [0, 255, 255]);
  });

  test('전부 배경이면 전부 투명하다', () async {
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([1, 1, 1, 1])),
    );
    expect(await _alphaRow(mask), [0, 0, 0, 0]);
  });
}
