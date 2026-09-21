import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

void main() {
  group('영역 ID 상수', () {
    test('선은 0, 배경은 1, 칠할 수 있는 영역은 2부터', () {
      expect(kRegionLine, 0);
      expect(kRegionBackground, 1);
      expect(kRegionFirstFillable, 2);
      expect(kMaxRegionId, 0xFFFF);
    });
  });

  group('인덱스맵 ID 인코딩', () {
    test('0부터 65535까지 왕복이 손실 없이 된다', () {
      for (final id in [0, 1, 2, 127, 255, 256, 257, 4096, 65534, 65535]) {
        final rgba = encodeRegionId(id);
        expect(rgba.length, 4, reason: 'RGBA 4바이트여야 한다');
        expect(rgba[2], 0, reason: 'B 채널은 예약되어 0이다');
        expect(rgba[3], 255, reason: 'A 채널은 항상 불투명하다');
        expect(decodeRegionId(rgba[0], rgba[1]), id,
            reason: 'ID $id 왕복 실패');
      }
    });

    test('R은 하위 8bit, G는 상위 8bit', () {
      expect(encodeRegionId(0x1234), [0x34, 0x12, 0, 255]);
    });
  });

  group('RegionMap', () {
    test('좌표 접근과 영역 개수 집계', () {
      final map = RegionMap.filled(4, 3, kRegionBackground);
      map.set(1, 1, 5);
      map.set(2, 1, 5);
      map.set(3, 2, 7);

      expect(map.at(1, 1), 5);
      expect(map.at(0, 0), kRegionBackground);
      expect(map.fillableRegionIds, {5, 7});
      expect(map.fillableRegionCount, 2);
      expect(map.areaByRegion()[5], 2);
      expect(map.areaByRegion()[kRegionBackground], 9);
    });
  });

  group('BinaryMask', () {
    test('선 픽셀 설정과 집계', () {
      final mask = BinaryMask.blank(3, 2);
      expect(mask.inkCount, 0);
      mask.setInk(1, 0, true);
      mask.setInk(2, 1, true);
      expect(mask.isInk(1, 0), isTrue);
      expect(mask.isInk(0, 0), isFalse);
      expect(mask.inkCount, 2);
    });
  });
}
