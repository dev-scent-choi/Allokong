import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('cleanupRegions', () {
    test('캔버스 테두리에 닿은 영역은 배경이 된다', () {
      final labeled = labelRegions(maskFromRows([
        '.......',
        '.#####.',
        '.#...#.',
        '.#...#.',
        '.#####.',
        '.......',
      ]));

      final cleaned = cleanupRegions(labeled, minArea: 1);

      expect(cleaned.at(0, 0), kRegionBackground, reason: '바깥 여백은 배경');
      expect(cleaned.at(3, 2), greaterThanOrEqualTo(kRegionFirstFillable),
          reason: '도형 내부는 칠할 수 있어야 한다');
      expect(cleaned.fillableRegionCount, 1);
    });

    test('배경으로 둘러싸인 도형이 여럿이면 각각 살아남는다', () {
      final labeled = labelRegions(maskFromRows([
        '............',
        '.###...###..',
        '.#.#...#.#..',
        '.###...###..',
        '............',
      ]));

      final cleaned = cleanupRegions(labeled, minArea: 1);

      expect(cleaned.fillableRegionCount, 2);
      expect(cleaned.at(2, 2), isNot(cleaned.at(8, 2)));
    });

    test('넓이가 기준 미만인 파편은 이웃 영역에 흡수된다', () {
      // 큰 방 하나와, 선 하나 건너 붙어 있는 1픽셀짜리 파편.
      final labeled = labelRegions(maskFromRows([
        '..........',
        '.########.',
        '.#......#.',
        '.#......#.',
        '.#......#.',
        '.########.',
        '.#.#......',
        '.###......',
        '..........',
      ]));

      final before = labeled.fillableRegionCount;
      final cleaned = cleanupRegions(labeled, minArea: 4, searchRadius: 3);

      expect(before, greaterThan(1));
      expect(cleaned.fillableRegionCount, 1,
          reason: '1픽셀 파편은 사라지고 큰 방만 남아야 한다');
    });

    test('정리 후 영역 ID는 2부터 빈틈없이 다시 부여된다', () {
      final labeled = labelRegions(maskFromRows([
        '............',
        '.###...###..',
        '.#.#...#.#..',
        '.###...###..',
        '............',
      ]));

      final cleaned = cleanupRegions(labeled, minArea: 1);

      expect(cleaned.fillableRegionIds, {2, 3});
    });

    test('칠할 수 있는 영역이 하나도 없어도 예외를 던지지 않는다', () {
      final labeled = labelRegions(maskFromRows([
        '....',
        '....',
      ]));

      final cleaned = cleanupRegions(labeled, minArea: 1);

      expect(cleaned.fillableRegionCount, 0);
      expect(cleaned.at(0, 0), kRegionBackground);
    });
  });
}
