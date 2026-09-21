import 'types.dart';

/// 스캔라인 방향으로 이어진 선 픽셀 길이의 중앙값으로 선 두께를 추정한다.
///
/// 평균이 아니라 중앙값을 쓰는 이유는, 가로로 누운 긴 선분 하나가 통계를
/// 끌어올리는 것을 막기 위해서다.
int estimateLineWidth(BinaryMask mask) {
  final runs = <int>[];
  for (var y = 0; y < mask.height; y++) {
    var run = 0;
    for (var x = 0; x < mask.width; x++) {
      if (mask.isInk(x, y)) {
        run++;
      } else {
        if (run > 0) runs.add(run);
        run = 0;
      }
    }
    if (run > 0) runs.add(run);
  }
  if (runs.isEmpty) return 1;
  runs.sort();
  return runs[runs.length ~/ 2];
}

BinaryMask _sweep(
  BinaryMask src,
  int radius, {
  required bool horizontal,
  required bool takeMax,
}) {
  final w = src.width;
  final h = src.height;
  final out = BinaryMask.blank(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var value = takeMax ? 0 : 1;
      for (var d = -radius; d <= radius; d++) {
        final xx = horizontal ? x + d : x;
        final yy = horizontal ? y : y + d;
        // 캔버스 밖은 여백(0)으로 본다. 도안에는 흰 여백이 있으므로
        // 선이 캔버스 경계에 닿는 경우는 없다고 전제한다.
        final v = (xx < 0 || yy < 0 || xx >= w || yy >= h)
            ? 0
            : src.ink[yy * w + xx];
        if (takeMax && v == 1) {
          value = 1;
          break;
        }
        if (!takeMax && v == 0) {
          value = 0;
          break;
        }
      }
      out.ink[y * w + x] = value;
    }
  }
  return out;
}

/// 사각 구조요소 팽창. 선을 [radius]만큼 사방으로 넓힌다.
BinaryMask dilate(BinaryMask mask, int radius) => _sweep(
      _sweep(mask, radius, horizontal: true, takeMax: true),
      radius,
      horizontal: false,
      takeMax: true,
    );

/// 사각 구조요소 침식. 선을 [radius]만큼 사방에서 깎는다.
BinaryMask erode(BinaryMask mask, int radius) => _sweep(
      _sweep(mask, radius, horizontal: true, takeMax: false),
      radius,
      horizontal: false,
      takeMax: false,
    );

/// 닫기 연산(팽창 후 침식). 끊긴 선의 틈을 메우되 선 두께는 대체로 보존한다.
///
/// [radius]를 주지 않으면 추정 선 두께의 절반을 쓴다. 이보다 크게 잡으면
/// 가느다란 디테일이 서로 붙어버리고, 작게 잡으면 틈이 남아 색이 샌다.
///
/// 최대 [radius]의 2배 너비까지 틈을 메울 수 있다.
BinaryMask closeLines(BinaryMask mask, {int? radius}) {
  final r = radius ?? (estimateLineWidth(mask) / 2).ceil().clamp(1, 8);
  if (r <= 0) return mask;
  return erode(dilate(mask, r), r);
}
