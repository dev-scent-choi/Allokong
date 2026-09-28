import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color, Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/canvas_transform.dart';
import 'package:kkumul/coloring/coloring_painter.dart';
import 'package:kkumul/coloring/fill_state.dart';
import 'package:kkumul/ui/coloring_screen.dart';

/// [FittedColoringPainter] 는 화면에 맞춰 `translate` 뒤 `scale` 을 건 다음
/// 안쪽 [ColoringPainter] 를 그대로 그린다. 두 줄의 순서가 바뀌어도(둘 다
/// 원점 기준이라) 셰이더가 그리는 결과 자체는 어긋나지 않을 수 있지만, 화면
/// 좌표 → 캔버스 좌표로 되짚는 [CanvasTransform.toView] 와 실제로 그려진
/// 화면 픽셀이 같은 곳을 가리키는지는 아무 테스트도 보지 않았다 — 리뷰가
/// 증명한 바로 그 구멍이다. 이 테스트는 셰이더가 아니라 그 배치 계약을 잠근다.
Future<ui.Image> _rgba(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 왼쪽 절반은 영역 2, 오른쪽 절반은 영역 3인 n×n 인덱스맵.
Future<ui.Image> _regionsHalf(int n) {
  final px = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final id = x < n ~/ 2 ? 2 : 3;
      final i = y * n + x;
      px[i * 4] = id & 0xFF;
      px[i * 4 + 1] = (id >> 8) & 0xFF;
      px[i * 4 + 3] = 255;
    }
  }
  return _rgba(px, n, n);
}

Future<ui.Image> _transparent(int w, int h) =>
    _rgba(Uint8List(w * h * 4), w, h);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      '캔버스 좌표가 화면 변환(이동+확대)을 거쳐도 실제로 그려진 픽셀과 '
      'toView() 가 가리키는 자리가 일치한다', () async {
    const n = 8;
    final regions = await _regionsHalf(n);
    final lineart = await _transparent(n, n);

    final fills = FillState()..setFill(2, const Color(0xFFFF0000));
    final palette = await fills.paletteImage();

    final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
    final inner = ColoringPainter(
      shader: program.fragmentShader(),
      regions: regions,
      palette: palette,
      lineart: lineart,
      canvasSize: n,
    );

    // 정사각형이 아닌 뷰를 써서 scale != 1.0, offset != (0,0) 을 둘 다
    // 강제한다 — 둘 중 하나가 0/1 이면 순서를 바꿔도 결과가 같아서
    // 테스트가 아무것도 구분하지 못한다.
    const viewSize = Size(50, 40);
    final transform = CanvasTransform.fit(viewSize, n);
    expect(transform.scale, isNot(1.0));
    expect(transform.offset.dx, isNot(0.0));

    final painter = FittedColoringPainter(transform: transform, inner: inner);

    final rec = ui.PictureRecorder();
    painter.paint(ui.Canvas(rec), viewSize);
    final out = await rec
        .endRecording()
        .toImage(viewSize.width.round(), viewSize.height.round());
    final d = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    List<int> pixelAt(int x, int y) {
      final i = (y * viewSize.width.round() + x) * 4;
      return [
        d.getUint8(i),
        d.getUint8(i + 1),
        d.getUint8(i + 2),
        d.getUint8(i + 3),
      ];
    }

    // 캔버스 좌표 (2.5, 4.5) 는 영역 2(빨강) 안쪽이고, 5배 확대에서 가장
    // 가까운 경계로부터도 2 화면픽셀 이상 떨어져 있다 — 최근접 샘플링의
    // 경계 흔들림에 걸리지 않는다.
    const canvasPoint = Offset(2.5, 4.5);
    final viewPoint = transform.toView(canvasPoint);
    final actual = pixelAt(viewPoint.dx.floor(), viewPoint.dy.floor());

    expect(actual, [255, 0, 0, 255],
        reason: '아이가 누른 칸(캔버스 2.5,4.5 = 영역 2)이 화면에서도 '
            '같은 자리에 빨갛게 보여야 한다');
  });
}
