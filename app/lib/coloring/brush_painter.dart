import 'dart:ui' as ui;

import 'brush_state.dart';

/// 브러시 레이어를 그린다.
///
/// 오프스크린 이미지에 누적하지 않고 매 프레임 스트로크 목록을 재생한다 —
/// 획 50개 × 점 100개 기록이 실측 2ms 라 프레임 예산(16.7ms) 안에 넉넉하다.
class BrushPainter {
  /// 브러시 레이어 한 겹을 [canvas] 에 합성한다.
  ///
  /// [mask] 는 칠할 수 있는 픽셀만 불투명한 이미지다. `dstIn` 으로 한 번
  /// 블렌드하면 선과 배경 위의 브러시가 잘려 나간다 — 상위 스펙 7.3 이
  /// 셰이더로 하라던 일과 결과가 같고 비용이 낮다(설계 문서 3.1절).
  static void paint(
    ui.Canvas canvas,
    ui.Rect bounds,
    BrushState brush,
    ui.Image? mask,
  ) {
    final live = brush.live;
    final base = brush.base;
    if (base == null && brush.strokes.isEmpty && live == null) return;

    // saveLayer 가 필요하다. 지우개의 BlendMode.clear 와 마스크의 dstIn 이
    // 브러시 레이어 안에서만 작용해야 하고, 밑에 깔린 채움 레이어를 건드리면
    // 안 된다.
    canvas.saveLayer(bounds, ui.Paint());

    if (base != null) {
      canvas.drawImage(base, ui.Offset.zero, ui.Paint());
    }
    for (final s in brush.strokes) {
      drawStroke(canvas, s);
    }
    if (live != null) {
      drawStroke(canvas, live);
    }
    if (mask != null) {
      canvas.drawImage(
        mask,
        ui.Offset.zero,
        ui.Paint()..blendMode = ui.BlendMode.dstIn,
      );
    }

    canvas.restore();
  }

  static void drawStroke(ui.Canvas canvas, Stroke s) {
    if (s.points.isEmpty) return;

    final paint = ui.Paint()
      ..strokeWidth = s.width
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..style = ui.PaintingStyle.stroke
      ..isAntiAlias = true;

    if (s.kind == BrushKind.eraser) {
      // 지우개는 색이 아니라 구멍이다. saveLayer 안에서만 뚫는다.
      paint.blendMode = ui.BlendMode.clear;
    } else {
      // 크레용은 살짝 비친다 — 겹쳐 그으면 진해지는 것이 실제 크레용에 가깝다.
      paint.color = s.kind == BrushKind.crayon
          ? s.color.withValues(alpha: 0.85)
          : s.color;
    }

    if (s.points.length == 1) {
      // 점 하나는 stroke 로 아무것도 그려지지 않는다. 원으로 찍는다.
      canvas.drawCircle(
        s.points.first,
        s.width / 2,
        ui.Paint()
          ..color = paint.color
          ..blendMode = paint.blendMode
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.fill,
      );
      return;
    }

    final path = ui.Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (final p in s.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}
