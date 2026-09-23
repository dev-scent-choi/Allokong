import 'package:image/image.dart' as img;

import 'types.dart';

/// 원본을 정사각 캔버스에 흰 여백과 함께 비율을 지켜 맞춰 넣는다.
///
/// 입력 이미지의 크기와 비율이 제각각이어도 도안 캔버스는 항상 같아야 한다.
/// 잘라내지 않고 여백을 주는 이유는 그림이 잘리면 안 되기 때문이다.
///
/// 파이프라인에 넣기 전에 반드시 거쳐야 하는 단계다. binarize 의 창 크기와
/// closeLines 의 반지름 상한은 절대 픽셀 값이라, 원본 해상도로 돌리면 같은
/// 그림이라도 다른 결과가 나온다.
img.Image fitToCanvas(img.Image src, int size) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  final longest = src.width > src.height ? src.width : src.height;
  final scale = size / longest;
  final w = (src.width * scale).round();
  final h = (src.height * scale).round();
  final resized = img.copyResize(
    src,
    width: w,
    height: h,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    resized,
    dstX: (size - w) ~/ 2,
    dstY: (size - h) ~/ 2,
  );
  return canvas;
}

/// 선 마스크를 알파 채널이 있는 검정 선화 이미지로 바꾼다.
///
/// 여백은 투명하게 둔다. 도안을 칠한 결과 위에 이 선화를 얹어야 하므로
/// 불투명한 흰색이면 칠한 색을 가린다.
img.Image inkToImage(BinaryMask mask) {
  final im = img.Image(width: mask.width, height: mask.height, numChannels: 4);
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      im.setPixelRgba(x, y, 0, 0, 0, mask.isInk(x, y) ? 255 : 0);
    }
  }
  return im;
}
