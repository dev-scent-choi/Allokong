import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'types.dart';

/// 이미지를 8bit 그레이스케일 격자로 변환한다.
Uint8List toGrayscale(img.Image src) {
  final out = Uint8List(src.width * src.height);
  var i = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      out[i++] = img.getLuminance(src.getPixel(x, y)).round().clamp(0, 255);
    }
  }
  return out;
}

/// 지역 평균 기반 적응형 이진화.
///
/// 픽셀 밝기가 주변 [window]×[window] 평균보다 [offset] 이상 어두우면 선으로
/// 본다. 전역 임계값과 달리 사진의 그림자나 기울어진 조명에서도 선을 잃지
/// 않는다. 적분 영상을 써서 창 크기와 무관하게 O(픽셀 수)로 동작한다.
BinaryMask binarize(img.Image src, {int window = 31, int offset = 10}) {
  final w = src.width;
  final h = src.height;
  final gray = toGrayscale(src);

  // 적분 영상: (w+1) × (h+1), integral[y+1][x+1] = 좌상단 직사각형의 합
  final integral = Int64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    for (var x = 0; x < w; x++) {
      rowSum += gray[y * w + x];
      integral[(y + 1) * (w + 1) + (x + 1)] =
          integral[y * (w + 1) + (x + 1)] + rowSum;
    }
  }

  int rectSum(int x0, int y0, int x1, int y1) => (integral[(y1 + 1) * (w + 1) + (x1 + 1)] -
          integral[y0 * (w + 1) + (x1 + 1)] -
          integral[(y1 + 1) * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0])
      .toInt();

  final r = window ~/ 2;
  final mask = BinaryMask.blank(w, h);
  for (var y = 0; y < h; y++) {
    final y0 = y - r < 0 ? 0 : y - r;
    final y1 = y + r >= h ? h - 1 : y + r;
    for (var x = 0; x < w; x++) {
      final x0 = x - r < 0 ? 0 : x - r;
      final x1 = x + r >= w ? w - 1 : x + r;
      final count = (x1 - x0 + 1) * (y1 - y0 + 1);
      final mean = rectSum(x0, y0, x1, y1) / count;
      mask.ink[y * w + x] = gray[y * w + x] < mean - offset ? 1 : 0;
    }
  }
  return mask;
}
