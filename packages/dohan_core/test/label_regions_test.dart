import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('labelRegions', () {
    test('선 픽셀은 영역 0을 유지한다', () {
      final map = labelRegions(maskFromRows([
        '.#.',
        '.#.',
      ]));

      expect(map.at(1, 0), kRegionLine);
      expect(map.at(1, 1), kRegionLine);
    });

    test('선이 없으면 여백 전체가 영역 하나다', () {
      final map = labelRegions(maskFromRows([
        '....',
        '....',
      ]));

      expect(map.fillableRegionIds, {kRegionFirstFillable});
    });

    test('세로선이 캔버스를 둘로 가르면 영역이 둘이다', () {
      final map = labelRegions(maskFromRows([
        '..#..',
        '..#..',
        '..#..',
      ]));

      expect(map.fillableRegionCount, 2);
      expect(map.at(0, 0), isNot(map.at(4, 0)),
          reason: '선 왼쪽과 오른쪽은 다른 영역이어야 한다');
    });

    test('닫힌 도형의 안과 밖은 다른 영역이다', () {
      final map = labelRegions(maskFromRows([
        '.......',
        '.#####.',
        '.#...#.',
        '.#...#.',
        '.#####.',
        '.......',
      ]));

      expect(map.fillableRegionCount, 2, reason: '바깥 여백 + 도형 내부');
      expect(map.at(3, 2), isNot(map.at(0, 0)));
    });

    test('대각선으로만 닿은 두 여백은 서로 다른 영역이다', () {
      // 4방 연결을 쓰므로 대각 접촉은 이어지지 않는다. 대각으로 이어진 것을
      // 같은 영역으로 보면, 선이 대각으로 지날 때 색이 새어나간다.
      final map = labelRegions(maskFromRows([
        '.#',
        '#.',
      ]));

      expect(map.fillableRegionCount, 2);
    });

    test('영역 ID는 2부터 빈틈없이 부여된다', () {
      final map = labelRegions(maskFromRows([
        '.#.#.',
        '.#.#.',
      ]));

      expect(map.fillableRegionIds, {2, 3, 4});
    });
  });
}
