import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

void main() {
  group('renderRegionPreview', () {
    test('선은 검정, 배경은 연회색으로 칠한다', () {
      final map = RegionMap.filled(4, 1, kRegionBackground);
      map.set(0, 0, kRegionLine);

      final im = renderRegionPreview(map);

      final line = im.getPixel(0, 0);
      expect([line.r.toInt(), line.g.toInt(), line.b.toInt()], [0, 0, 0]);

      final bg = im.getPixel(1, 0);
      expect(bg.r.toInt(), greaterThan(220));
      expect(bg.r.toInt(), bg.g.toInt());
      expect(bg.g.toInt(), bg.b.toInt());
    });

    test('서로 다른 영역은 서로 다른 색을 받는다', () {
      final map = RegionMap.filled(4, 1, kRegionBackground);
      map.set(0, 0, 2);
      map.set(1, 0, 3);
      map.set(2, 0, 4);

      final im = renderRegionPreview(map);

      final colors = [0, 1, 2].map((x) {
        final p = im.getPixel(x, 0);
        return '${p.r}-${p.g}-${p.b}';
      }).toSet();

      expect(colors.length, 3, reason: '영역 색이 겹치면 검수를 못 한다');
    });

    test('같은 영역은 같은 색을 받는다', () {
      final map = RegionMap.filled(4, 1, kRegionBackground);
      map.set(0, 0, 2);
      map.set(3, 0, 2);

      final im = renderRegionPreview(map);
      final a = im.getPixel(0, 0);
      final b = im.getPixel(3, 0);

      expect(a.r, b.r);
      expect(a.g, b.g);
      expect(a.b, b.b);
    });

    test('같은 seed면 같은 결과가 나온다', () {
      final map = RegionMap.filled(4, 1, kRegionBackground);
      map.set(0, 0, 2);

      final a = renderRegionPreview(map, seed: 7).getPixel(0, 0);
      final b = renderRegionPreview(map, seed: 7).getPixel(0, 0);

      expect(a.r, b.r);
      expect(a.g, b.g);
      expect(a.b, b.b);
    });
  });
}
