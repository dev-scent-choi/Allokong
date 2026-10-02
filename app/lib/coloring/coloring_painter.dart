import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'brush_painter.dart';
import 'brush_state.dart';
import 'sticker_state.dart';

/// 도안 한 장을 그린다.
///
/// 아래에서 위로: 흰 배경 → 채움(셰이더) → 브러시 → 선화 → 스티커.
///
/// 좌표계는 도안의 논리 캔버스([canvasSize] × [canvasSize])다. 화면에 맞추는
/// 확대·이동은 호출하는 쪽이 캔버스 변환으로 건다 — `FlutterFragCoord()` 가
/// 로컬 좌표라 셰이더는 변환을 그대로 따라간다.
class ColoringPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image regions;
  final ui.Image palette;
  final ui.Image lineart;
  final int canvasSize;
  final BrushState? brush;
  final int brushRevision;
  final ui.Image? paintableMask;
  final List<Sticker> stickers;
  final Map<String, ui.Image> stickerImages;

  ColoringPainter({
    required this.shader,
    required this.regions,
    required this.palette,
    required this.lineart,
    required this.canvasSize,
    this.brush,
    this.brushRevision = 0,
    this.paintableMask,
    this.stickers = const [],
    this.stickerImages = const {},
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final rect = ui.Rect.fromLTWH(
      0,
      0,
      canvasSize.toDouble(),
      canvasSize.toDouble(),
    );

    // 1) 흰 배경
    canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFFFFFFF));

    // 2) 채움 레이어
    shader
      ..setFloat(0, canvasSize.toDouble())
      ..setFloat(1, canvasSize.toDouble())
      ..setFloat(2, regions.width.toDouble())
      ..setFloat(3, regions.height.toDouble())
      ..setImageSampler(0, regions)
      ..setImageSampler(1, palette);
    canvas.drawRect(rect, ui.Paint()..shader = shader);

    // 3. 브러시 — 선화 아래다. 선이 항상 살아 있어야 한다.
    final b = brush;
    if (b != null) {
      BrushPainter.paint(
        canvas,
        ui.Rect.fromLTWH(0, 0, canvasSize.toDouble(), canvasSize.toDouble()),
        b,
        paintableMask,
      );
    }

    // 4) 선화
    canvas.drawImageRect(
      lineart,
      ui.Rect.fromLTWH(
        0,
        0,
        lineart.width.toDouble(),
        lineart.height.toDouble(),
      ),
      rect,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );

    // 5. 스티커 — 선화 위다. 스티커가 선에 가리면 안 된다(상위 스펙 7.1).
    for (final s in stickers) {
      final img = stickerImages[s.stickerId];
      if (img == null) continue;
      canvas.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        s.bounds,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    }
  }

  @override
  bool shouldRepaint(ColoringPainter old) {
    // 항상 다시 그린다.
    //
    // 이 페인터는 컨트롤러가 "뭔가 바뀌었다"고 알렸을 때만 새로 만들어진다.
    // 즉 "새로 만들어졌다"가 곧 "다시 그려야 한다"이다.
    //
    // 세밀하게 비교하려다 두 가지를 놓쳤었다 — 긋는 중인 획은 `BrushState.live`
    // 에 있어서 `revision` 을 올리지 않고, 스티커 드래그는 `replaceAt` 이라
    // 목록 길이가 그대로다. 둘 다 "안 바뀌었다"로 읽혀서, 아이가 손가락을 끄는
    // 동안 화면에 아무것도 나타나지 않고 손을 뗄 때 획이 통째로 튀어나왔다.
    return true;
  }
}
