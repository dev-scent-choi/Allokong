import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/coloring_painter.dart';
import 'package:kkumul/coloring/fill_state.dart';

typedef Size = ui.Size;

Future<ui.Image> _rgba(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 영역 ID 를 R/G 에 인코딩한 가로 줄 인덱스맵.
Future<ui.Image> _regionStrip(List<int> ids) {
  final px = Uint8List(ids.length * 4);
  for (var i = 0; i < ids.length; i++) {
    px[i * 4] = ids[i] & 0xFF;
    px[i * 4 + 1] = (ids[i] >> 8) & 0xFF;
    px[i * 4 + 3] = 255;
  }
  return _rgba(px, ids.length, 1);
}

Future<ui.Image> _transparent(int w, int h) =>
    _rgba(Uint8List(w * h * 4), w, h);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('셰이더가 ID 를 디코딩하고 팔레트에서 색을 찾는다', () async {
    const ids = [0, 1, 2, 3, 300];
    final regions = await _regionStrip(ids);
    final lineart = await _transparent(ids.length, 1);

    final fills = FillState()
      ..setFill(2, const Color(0xFFFF0000))
      ..setFill(300, const Color(0xFF0000FF));
    // ID 3 은 일부러 비워 둔다 = 미채색
    final palette = await fills.paletteImage();

    final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
    final painter = ColoringPainter(
      shader: program.fragmentShader(),
      regions: regions,
      palette: palette,
      lineart: lineart,
      canvasSize: ids.length,
    );

    final rec = ui.PictureRecorder();
    painter.paint(ui.Canvas(rec), Size(ids.length.toDouble(), 1));
    final out = await rec.endRecording().toImage(ids.length, 1);
    final d = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    List<int> at(int x) => [
          d.getUint8(x * 4),
          d.getUint8(x * 4 + 1),
          d.getUint8(x * 4 + 2),
          d.getUint8(x * 4 + 3),
        ];

    expect(at(0), [255, 255, 255, 255], reason: '선 자리도 흰 배경이 비친다');
    expect(at(1), [255, 255, 255, 255], reason: '배경 자리도 흰 배경');
    expect(at(2), [255, 0, 0, 255], reason: 'ID 2 는 빨강');
    expect(at(3), [255, 255, 255, 255], reason: '미채색은 흰 배경이 비친다');
    expect(at(4), [0, 0, 255, 255], reason: 'ID 300 — 상위 바이트 경로');
  });

  test('칠하지 않은 도안은 전부 흰 배경이다', () async {
    const ids = [2, 3, 4, 5];
    final regions = await _regionStrip(ids);
    final lineart = await _transparent(ids.length, 1);
    final palette = await FillState().paletteImage();

    final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
    final rec = ui.PictureRecorder();
    ColoringPainter(
      shader: program.fragmentShader(),
      regions: regions,
      palette: palette,
      lineart: lineart,
      canvasSize: ids.length,
    ).paint(ui.Canvas(rec), Size(ids.length.toDouble(), 1));

    final out = await rec.endRecording().toImage(ids.length, 1);
    final d = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    for (var x = 0; x < ids.length; x++) {
      expect(d.getUint8(x * 4 + 3), 255);
      expect(d.getUint8(x * 4), 255, reason: '$x 번 픽셀이 흰색이어야 한다');
    }
  });
}
