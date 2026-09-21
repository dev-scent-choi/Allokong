import 'dart:typed_data';

import 'types.dart';

/// 선 두께를 추정한다.
///
/// 각 선 픽셀에서 가로로 이어진 길이와 세로로 이어진 길이 중 **작은 쪽**을
/// 그 픽셀의 두께로 보고, 전체의 중앙값을 취한다. 가로 런만 재면 길게 누운
/// 획의 *길이*를 두께로 착각해(길이 20의 3픽셀 획 → 20) 보정 반지름이 과도
/// 하게 커지고 가까운 디테일끼리 붙어버린다. 평균이 아니라 중앙값을 쓰는
/// 것은 몇 개의 굵은 덩어리가 통계를 끌어올리는 것을 막기 위해서다.
int estimateLineWidth(BinaryMask mask) {
  final w = mask.width;
  final h = mask.height;
  final horizontal = Int32List(w * h);
  final vertical = Int32List(w * h);

  for (var y = 0; y < h; y++) {
    var x = 0;
    while (x < w) {
      if (mask.ink[y * w + x] == 0) {
        x++;
        continue;
      }
      final start = x;
      while (x < w && mask.ink[y * w + x] == 1) {
        x++;
      }
      for (var i = start; i < x; i++) {
        horizontal[y * w + i] = x - start;
      }
    }
  }

  for (var x = 0; x < w; x++) {
    var y = 0;
    while (y < h) {
      if (mask.ink[y * w + x] == 0) {
        y++;
        continue;
      }
      final start = y;
      while (y < h && mask.ink[y * w + x] == 1) {
        y++;
      }
      for (var i = start; i < y; i++) {
        vertical[i * w + x] = y - start;
      }
    }
  }

  final widths = <int>[];
  for (var i = 0; i < w * h; i++) {
    if (mask.ink[i] == 0) continue;
    final hr = horizontal[i];
    final vr = vertical[i];
    widths.add(hr < vr ? hr : vr);
  }
  if (widths.isEmpty) return 1;
  widths.sort();
  return widths[widths.length ~/ 2];
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
        // 캔버스 밖은 연산에 따라 다르게 본다. 팽창에서는 여백(0)으로 보아
        // 선이 캔버스 밖으로 자라지 않게 하고, 침식에서는 선(1)으로 보아
        // 경계에 닿은 선이 깎여 사라지지 않게 한다. 둘 다 0으로 두면 침식이
        // 테두리에서 radius 폭만큼 진짜 선을 지워, 보정이 오히려 색이 새는
        // 틈을 만든다.
        final v = (xx < 0 || yy < 0 || xx >= w || yy >= h)
            ? (takeMax ? 0 : 1)
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
