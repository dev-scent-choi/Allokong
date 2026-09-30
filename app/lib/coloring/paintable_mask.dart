import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';

/// 칠할 수 있는 픽셀만 불투명한 마스크를 만든다.
///
/// 상위 스펙 7.3 은 브러시를 합성할 때 셰이더가 픽셀마다 `regionId >= 2` 를
/// 확인하라고 하지만, 칠할 수 있는지 아닌지는 **도안마다 고정**이라 런타임에
/// 픽셀마다 물을 이유가 없다. 도안을 읽을 때 한 번 만들어두고 `BlendMode.dstIn`
/// 으로 한 번 블렌드하면 결과가 같다 — 설계 문서 3.1절.
///
/// 1024² 에서 7ms 걸린다(실측). 도안당 한 번이다.
Future<ui.Image> buildPaintableMask(RegionMap regions) {
  final n = regions.width * regions.height;
  final px = Uint8List(n * 4);
  for (var i = 0; i < n; i++) {
    if (regions.ids[i] >= kRegionFirstFillable) {
      final o = i * 4;
      px[o] = 255;
      px[o + 1] = 255;
      px[o + 2] = 255;
      px[o + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    px,
    regions.width,
    regions.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
