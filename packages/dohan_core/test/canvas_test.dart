import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// 지정한 색으로 꽉 찬 이미지.
img.Image _solid(int w, int h, img.Color color) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: color);
  return im;
}

bool _isWhite(img.Pixel p) => p.r == 255 && p.g == 255 && p.b == 255;

void main() {
  final red = img.ColorRgba8(255, 0, 0, 255);

  group('fitToCanvas', () {
    test('정사각 원본은 여백 없이 캔버스를 채운다', () {
      final out = fitToCanvas(_solid(50, 50, red), 128);

      expect(out.width, 128);
      expect(out.height, 128);
      expect(_isWhite(out.getPixel(1, 1)), isFalse,
          reason: '여백이 생기면 안 된다');
      expect(_isWhite(out.getPixel(126, 126)), isFalse);
    });

    test('가로로 긴 원본은 위아래에 흰 여백이 생긴다', () {
      // 200x100 -> 128 캔버스: 폭 128, 높이 64, dstY = 32
      final out = fitToCanvas(_solid(200, 100, red), 128);

      expect(_isWhite(out.getPixel(64, 2)), isTrue, reason: '위쪽 여백');
      expect(_isWhite(out.getPixel(64, 125)), isTrue, reason: '아래쪽 여백');
      expect(_isWhite(out.getPixel(64, 64)), isFalse, reason: '가운데는 그림');
      expect(_isWhite(out.getPixel(2, 64)), isFalse,
          reason: '가로는 캔버스를 꽉 채운다');
    });

    test('세로로 긴 원본은 좌우에 흰 여백이 생긴다', () {
      // 100x200 -> 128 캔버스: 폭 64, 높이 128, dstX = 32
      final out = fitToCanvas(_solid(100, 200, red), 128);

      expect(_isWhite(out.getPixel(2, 64)), isTrue, reason: '왼쪽 여백');
      expect(_isWhite(out.getPixel(125, 64)), isTrue, reason: '오른쪽 여백');
      expect(_isWhite(out.getPixel(64, 64)), isFalse, reason: '가운데는 그림');
      expect(_isWhite(out.getPixel(64, 2)), isFalse,
          reason: '세로는 캔버스를 꽉 채운다');
    });

    test('원본보다 큰 캔버스로도 비율을 지킨다', () {
      final out = fitToCanvas(_solid(10, 20, red), 200);

      expect(out.width, 200);
      expect(out.height, 200);
      expect(_isWhite(out.getPixel(5, 100)), isTrue);
      expect(_isWhite(out.getPixel(100, 100)), isFalse);
    });
  });

  group('inkToImage', () {
    test('선은 불투명한 검정, 여백은 완전히 투명하다', () {
      final mask = BinaryMask.blank(4, 2);
      mask.setInk(1, 0, true);

      final im = inkToImage(mask);

      expect(im.width, 4);
      expect(im.height, 2);

      final ink = im.getPixel(1, 0);
      expect([ink.r, ink.g, ink.b, ink.a], [0, 0, 0, 255]);

      final paper = im.getPixel(0, 0);
      expect(paper.a, 0, reason: '여백이 불투명하면 칠한 색을 가린다');
    });
  });
}
