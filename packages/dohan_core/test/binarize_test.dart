import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// 흰 배경에 검은 수직 막대가 있는 테스트 이미지.
img.Image _barImage({int size = 64, int barX = 30, int barWidth = 4}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
  for (var y = 0; y < size; y++) {
    for (var x = barX; x < barX + barWidth; x++) {
      im.setPixelRgba(x, y, 0, 0, 0, 255);
    }
  }
  return im;
}

void main() {
  group('toGrayscale', () {
    test('흰색은 255, 검은색은 0에 가깝다', () {
      final im = _barImage();
      final gray = toGrayscale(im);
      expect(gray.length, 64 * 64);
      expect(gray[0], greaterThan(250), reason: '좌상단은 흰 배경');
      expect(gray[0 * 64 + 31], lessThan(5), reason: '막대 내부는 검정');
    });
  });

  group('binarize', () {
    test('검은 막대는 선으로, 흰 배경은 여백으로 분류한다', () {
      final mask = binarize(_barImage());

      expect(mask.isInk(31, 10), isTrue, reason: '막대 중심은 선이어야 한다');
      expect(mask.isInk(0, 0), isFalse, reason: '멀리 떨어진 배경은 여백');
      expect(mask.isInk(63, 63), isFalse);
    });

    test('완전히 흰 이미지에는 선이 하나도 없다', () {
      final im = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));

      expect(binarize(im).inkCount, 0);
    });

    test('조명이 기울어도 선을 놓치지 않는다', () {
      // 왼쪽은 밝고 오른쪽으로 갈수록 어두워지는 배경 위의 검은 막대.
      final im = img.Image(width: 64, height: 64, numChannels: 4);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final v = 255 - x * 2; // 255 → 129
          im.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      for (var y = 0; y < 64; y++) {
        for (var x = 50; x < 54; x++) {
          im.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }

      final mask = binarize(im);
      expect(mask.isInk(51, 32), isTrue,
          reason: '어두운 영역에 있어도 막대는 지역 평균보다 훨씬 어둡다');
      expect(mask.isInk(20, 32), isFalse,
          reason: '기울어진 배경 자체는 선이 아니다');
    });

    test('투명한 배경은 흰 종이로 보고 선을 찾아낸다', () {
      // 알파 0 인 배경 위에 불투명한 검은 막대. 알파를 무시하면 전부 검정으로
      // 읽혀 선이 하나도 검출되지 않는다.
      final im = img.Image(width: 64, height: 64, numChannels: 4);
      img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
      for (var y = 0; y < 64; y++) {
        for (var x = 30; x < 34; x++) {
          im.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }

      final mask = binarize(im);

      expect(mask.isInk(31, 10), isTrue, reason: '막대는 선이어야 한다');
      expect(mask.isInk(5, 10), isFalse, reason: '투명한 배경은 여백이다');
    });
  });
}
