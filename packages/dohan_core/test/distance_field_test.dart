import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

void main() {
  group('smallestInscribedDiameter', () {
    test('칠할 수 있는 영역이 없으면 0', () {
      expect(smallestInscribedDiameter(RegionMap.filled(4, 4, kRegionBackground)), 0);
    });

    test('정사각 영역의 지름은 폭과 같다', () {
      // 7x7 캔버스 한가운데 5x5 영역. 경계에서의 최대 체비셰프 거리는 2 이므로
      // 지름은 2*2+1 = 5 다.
      final map = RegionMap.filled(7, 7, kRegionLine);
      for (var y = 1; y <= 5; y++) {
        for (var x = 1; x <= 5; x++) {
          map.set(x, y, 2);
        }
      }

      expect(smallestInscribedDiameter(map), 5);
    });

    test('영역이 여럿이면 가장 작은 쪽을 돌려준다', () {
      final map = RegionMap.filled(13, 7, kRegionLine);
      for (var y = 1; y <= 5; y++) {
        for (var x = 1; x <= 5; x++) {
          map.set(x, y, 2);
        }
      }
      for (var y = 3; y <= 3; y++) {
        for (var x = 8; x <= 10; x++) {
          map.set(x, y, 3);
        }
      }

      expect(smallestInscribedDiameter(map), 1,
          reason: '1픽셀 두께 영역의 내접 지름은 1 이다');
    });
  });
}
