import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  group('인덱스맵 PNG', () {
    test('영역 ID가 손실 없이 왕복한다', () {
      final map = RegionMap.filled(8, 4, kRegionBackground);
      map.set(0, 0, kRegionLine);
      map.set(1, 0, 2);
      map.set(2, 0, 255);
      map.set(3, 0, 256);
      map.set(4, 0, 4096);
      map.set(5, 0, 65535);

      final restored = decodeIndexMapPng(encodeIndexMapPng(map));

      expect(restored.width, 8);
      expect(restored.height, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 8; x++) {
          expect(restored.at(x, y), map.at(x, y),
              reason: '($x, $y) 왕복 실패');
        }
      }
    });

    test('B 채널은 0, A 채널은 255로 기록된다', () {
      final map = RegionMap.filled(2, 2, 300);

      final im = img.decodePng(encodeIndexMapPng(map))!;
      final p = im.getPixel(0, 0);

      expect(p.r.toInt(), 300 & 0xFF);
      expect(p.g.toInt(), 300 >> 8);
      expect(p.b.toInt(), 0);
      expect(p.a.toInt(), 255);
    });

    test('1024×1024 맵도 왕복한다', () {
      final map = RegionMap.filled(1024, 1024, kRegionBackground);
      for (var i = 0; i < 1024; i++) {
        map.set(i, i, kRegionFirstFillable + (i % 500));
      }

      final restored = decodeIndexMapPng(encodeIndexMapPng(map));

      for (var i = 0; i < 1024; i += 37) {
        expect(restored.at(i, i), map.at(i, i));
      }
    });
  });
}
