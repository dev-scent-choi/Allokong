import 'dart:typed_data';
import 'dart:ui';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/canvas_transform.dart';

void main() {
  group('CanvasTransform.fit', () {
    test('가로로 넓은 화면에서는 좌우에 여백이 생긴다', () {
      final t = CanvasTransform.fit(const Size(400, 200), 100);

      expect(t.scale, 2.0, reason: '높이 200 / 캔버스 100');
      expect(t.offset, const Offset(100, 0), reason: '(400-200)/2');
    });

    test('세로로 긴 화면에서는 위아래에 여백이 생긴다', () {
      final t = CanvasTransform.fit(const Size(200, 400), 100);

      expect(t.scale, 2.0);
      expect(t.offset, const Offset(0, 100));
    });

    test('정사각 화면은 여백이 없다', () {
      final t = CanvasTransform.fit(const Size(300, 300), 100);

      expect(t.scale, 3.0);
      expect(t.offset, Offset.zero);
    });
  });

  group('좌표 왕복', () {
    test('toCanvas 와 toView 는 서로의 역이다', () {
      final t = CanvasTransform.fit(const Size(400, 200), 100);

      for (final p in [
        const Offset(100, 0),
        const Offset(300, 200),
        const Offset(200, 100),
      ]) {
        final back = t.toView(t.toCanvas(p));
        expect(back.dx, closeTo(p.dx, 1e-9));
        expect(back.dy, closeTo(p.dy, 1e-9));
      }
    });

    test('화면 가운데는 캔버스 가운데다', () {
      final t = CanvasTransform.fit(const Size(400, 200), 100);

      final c = t.toCanvas(const Offset(200, 100));

      expect(c.dx, closeTo(50, 1e-9));
      expect(c.dy, closeTo(50, 1e-9));
    });

    test('destRect 는 여백을 뺀 실제 그림 영역이다', () {
      final t = CanvasTransform.fit(const Size(400, 200), 100);

      expect(t.destRect, const Rect.fromLTWH(100, 0, 200, 200));
    });
  });

  group('regionAt', () {
    RegionMap threeStripes() {
      // 폭 6, 높이 2. 좌/중/우 두 칸씩 ID 2,3,4.
      final ids = Uint16List(12);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 6; x++) {
          ids[y * 6 + x] = 2 + x ~/ 2;
        }
      }
      return RegionMap(6, 2, ids);
    }

    test('캔버스 좌표의 영역 ID 를 읽는다', () {
      final r = threeStripes();

      expect(regionAt(r, const Offset(0.5, 0.5)), 2);
      expect(regionAt(r, const Offset(2.5, 0.5)), 3);
      expect(regionAt(r, const Offset(5.5, 1.5)), 4);
    });

    test('경계 바로 안쪽과 바깥쪽이 다른 영역이다', () {
      final r = threeStripes();

      expect(regionAt(r, const Offset(1.9, 0.5)), 2, reason: '경계 직전');
      expect(regionAt(r, const Offset(2.1, 0.5)), 3, reason: '경계 직후');
    });

    test('캔버스 밖은 배경으로 본다', () {
      final r = threeStripes();

      expect(regionAt(r, const Offset(-1, 0)), kRegionBackground);
      expect(regionAt(r, const Offset(0, -1)), kRegionBackground);
      expect(regionAt(r, const Offset(6, 0)), kRegionBackground);
      expect(regionAt(r, const Offset(0, 2)), kRegionBackground);
    });

    test('오른쪽·아래 끝 픽셀도 읽힌다', () {
      final r = threeStripes();

      expect(regionAt(r, const Offset(5.99, 1.99)), 4);
    });
  });
}
