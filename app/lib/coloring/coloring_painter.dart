import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// 도안 한 장을 그린다.
///
/// 아래에서 위로: 흰 배경 → 채움(셰이더) → 선화. 브러시와 스티커 층은
/// 계획 3 이 이 사이에 끼워 넣는다.
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

  ColoringPainter({
    required this.shader,
    required this.regions,
    required this.palette,
    required this.lineart,
    required this.canvasSize,
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

    // 3) 선화
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
  }

  @override
  bool shouldRepaint(ColoringPainter old) =>
      old.palette != palette ||
      old.regions != regions ||
      old.lineart != lineart ||
      old.canvasSize != canvasSize;
}
