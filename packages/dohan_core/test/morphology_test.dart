import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('estimateLineWidth', () {
    test('3픽셀 두께 선에서 3을 얻는다', () {
      final mask = maskFromRows([
        '..........',
        '...###....',
        '...###....',
        '...###....',
        '..........',
      ]);

      expect(estimateLineWidth(mask), 3);
    });

    test('선이 없으면 1을 반환한다', () {
      expect(estimateLineWidth(maskFromRows(['....', '....'])), 1);
    });

    test('길게 누운 획에서도 길이가 아니라 두께를 잰다', () {
      final mask = maskFromRows([
        '......................',
        '.####################.',
        '.####################.',
        '.####################.',
        '......................',
      ]);

      expect(estimateLineWidth(mask), 3,
          reason: '길이 20, 두께 3인 획의 두께는 3이다');
    });
  });

  group('dilate / erode', () {
    test('팽창은 선을 반지름만큼 넓힌다', () {
      final mask = maskFromRows([
        '.....',
        '.....',
        '..#..',
        '.....',
        '.....',
      ]);

      final grown = dilate(mask, 1);

      expect(rowsFromMask(grown), [
        '.....',
        '.###.',
        '.###.',
        '.###.',
        '.....',
      ]);
    });

    test('침식은 팽창을 되돌린다', () {
      final mask = maskFromRows([
        '.....',
        '.###.',
        '.###.',
        '.###.',
        '.....',
      ]);

      expect(rowsFromMask(erode(mask, 1)), [
        '.....',
        '.....',
        '..#..',
        '.....',
        '.....',
      ]);
    });
  });

  group('closeLines', () {
    test('끊긴 선의 틈을 메운다', () {
      // 세로선 한가운데가 2픽셀 끊겨 있다. 이대로 라벨링하면 안쪽과 바깥쪽이
      // 하나로 이어져 색이 새어나간다.
      final mask = maskFromRows([
        '.........',
        '....#....',
        '....#....',
        '....#....',
        '.........', // 틈
        '.........', // 틈
        '....#....',
        '....#....',
        '....#....',
        '.........',
      ]);

      expect(mask.isInk(4, 4), isFalse, reason: '보정 전에는 틈이 비어 있다');

      final closed = closeLines(mask, radius: 2);

      expect(closed.isInk(4, 4), isTrue, reason: '틈이 메워져야 한다');
      expect(closed.isInk(4, 5), isTrue, reason: '틈이 메워져야 한다');
    });

    test('반지름을 주지 않으면 선 두께에서 추정한다', () {
      final mask = maskFromRows([
        '..........',
        '..####....',
        '..####....',
        '..........',
        '..####....',
        '..####....',
        '..........',
      ]);

      // 선 두께 4 → 반지름 2 → 세로 1픽셀 틈은 메워진다.
      final closed = closeLines(mask);

      expect(closed.isInk(3, 3), isTrue);
    });

    test('닫힌 도형의 내부를 채우지는 않는다', () {
      final mask = maskFromRows([
        '.........',
        '.#######.',
        '.#.....#.',
        '.#.....#.',
        '.#.....#.',
        '.#######.',
        '.........',
      ]);

      final closed = closeLines(mask, radius: 1);

      expect(closed.isInk(4, 3), isFalse,
          reason: '도형 내부는 여백으로 남아야 칠할 수 있다');
    });
  });

  group('경계 처리', () {
    test('침식은 전부 선인 마스크를 그대로 둔다', () {
      final mask = maskFromRows([
        '#####',
        '#####',
        '#####',
        '#####',
        '#####',
      ]);

      expect(erode(mask, 1).inkCount, 25,
          reason: '캔버스 밖을 여백으로 보면 테두리 한 겹이 깎여 나간다');
    });

    test('보정이 테두리에 닿은 선을 잘라내지 않는다', () {
      // 캔버스 가장자리에 딱 붙은 테두리 도형. 침식이 캔버스 밖을 여백으로
      // 보면 이 테두리가 지워지고, 안과 밖이 이어져 색이 새어나간다.
      final mask = maskFromRows([
        '#######',
        '#.....#',
        '#.....#',
        '#.....#',
        '#######',
      ]);

      final closed = closeLines(mask, radius: 1);

      expect(closed.isInk(0, 0), isTrue);
      expect(closed.isInk(3, 0), isTrue);
      expect(closed.isInk(0, 2), isTrue);
      expect(closed.isInk(6, 4), isTrue);
      expect(closed.isInk(3, 2), isFalse,
          reason: '내부는 여전히 칠할 수 있어야 한다');
    });
  });
}
