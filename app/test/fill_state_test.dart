import 'dart:ui';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/fill_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// LUT 에서 영역 ID 의 RGBA 를 읽는다.
  List<int> lutAt(FillState s, int id) {
    final o = ((id >> 8) * 256 + (id & 0xFF)) * 4;
    return [
      s.lutBytes[o],
      s.lutBytes[o + 1],
      s.lutBytes[o + 2],
      s.lutBytes[o + 3],
    ];
  }

  test('처음에는 아무것도 칠해져 있지 않다', () {
    final s = FillState();

    expect(s.filledCount, 0);
    expect(s.fillOf(2), isNull);
    expect(lutAt(s, 2)[3], 0, reason: '알파 0 = 미채색');
  });

  test('영역 ID 를 LUT 좌표 (n%256, n~/256) 에 쓴다', () {
    final s = FillState();

    s.setFill(2, const Color(0xFFEF7586));
    s.setFill(300, const Color(0xFF6CAEE0));

    expect(lutAt(s, 2), [0xEF, 0x75, 0x86, 0xFF]);
    expect(lutAt(s, 300), [0x6C, 0xAE, 0xE0, 0xFF],
        reason: '상위 바이트가 있는 ID 도 제자리에 들어가야 한다');
  });

  test('null 을 주면 미채색으로 되돌린다', () {
    final s = FillState()..setFill(2, const Color(0xFFEF7586));

    s.setFill(2, null);

    expect(s.fillOf(2), isNull);
    expect(s.filledCount, 0);
    expect(lutAt(s, 2)[3], 0);
  });

  test('선(0)과 배경(1)은 칠할 수 없다', () {
    final s = FillState();

    expect(() => s.setFill(kRegionLine, const Color(0xFFFF0000)),
        throwsA(isA<ArgumentError>()));
    expect(() => s.setFill(kRegionBackground, const Color(0xFFFF0000)),
        throwsA(isA<ArgumentError>()));
  });

  test('JSON 으로 왕복한다', () {
    final s = FillState()
      ..setFill(2, const Color(0xFFEF7586))
      ..setFill(300, const Color(0xFF6CAEE0));

    final restored = FillState()..loadJson(s.toJson());

    expect(restored.fillOf(2), const Color(0xFFEF7586));
    expect(restored.fillOf(300), const Color(0xFF6CAEE0));
    expect(restored.filledCount, 2);
    expect(lutAt(restored, 300), [0x6C, 0xAE, 0xE0, 0xFF]);
  });

  test('팔레트 이미지는 256x256 이다', () async {
    final s = FillState()..setFill(2, const Color(0xFFEF7586));

    final im = await s.paletteImage();

    expect(im.width, 256);
    expect(im.height, 256);
  });
}
