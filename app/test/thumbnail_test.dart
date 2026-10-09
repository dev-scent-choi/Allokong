import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/coloring_painter.dart';
import 'package:kkumul/coloring/fill_state.dart';
import 'package:kkumul/gallery/thumbnail.dart';

Future<ui.Image> _rgba(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 왼쪽 절반이 ID 2, 오른쪽 절반이 ID 3 인 정사각 인덱스맵.
Future<ui.Image> _halves(int n) {
  final px = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final i = (y * n + x) * 4;
      final id = x < n ~/ 2 ? 2 : 3;
      px[i] = id & 0xFF;
      px[i + 1] = (id >> 8) & 0xFF;
      px[i + 3] = 255;
    }
  }
  return _rgba(px, n, n);
}

Future<ui.Image> _transparent(int w, int h) => _rgba(Uint8List(w * h * 4), w, h);

/// PNG 바이트를 디코딩해 픽셀을 읽을 수 있게 한다.
Future<(int, int, ByteData)> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final data =
      (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (frame.image.width, frame.image.height, data);
}

Future<ColoringPainter> _painter(int n, FillState fills) async {
  final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
  return ColoringPainter(
    shader: program.fragmentShader(),
    regions: await _halves(n),
    palette: await fills.paletteImage(),
    lineart: await _transparent(n, n),
    canvasSize: n,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('칠한 색이 썸네일 픽셀에 그대로 나온다', () async {
    const n = 64;
    final fills = FillState()..setFill(2, const Color(0xFFFF0000));

    final png = await bakeThumbnail(await _painter(n, fills), n);

    expect(png, isNotNull);
    final (w, h, d) = await _decode(png!);
    expect(w, kThumbnailSize);
    expect(h, kThumbnailSize);

    List<int> at(int x, int y) {
      final i = (y * w + x) * 4;
      return [d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2)];
    }

    expect(at(kThumbnailSize ~/ 4, kThumbnailSize ~/ 2), [255, 0, 0],
        reason: '왼쪽 절반은 칠한 빨강이어야 한다');
    expect(at(kThumbnailSize * 3 ~/ 4, kThumbnailSize ~/ 2), [255, 255, 255],
        reason: '칠하지 않은 오른쪽은 흰 배경이 비친다');
  });

  test('아무것도 안 칠해도 흰 정사각형이 나온다', () async {
    const n = 64;

    final png = await bakeThumbnail(await _painter(n, FillState()), n);

    final (w, h, d) = await _decode(png!);
    expect(w, kThumbnailSize);
    expect(h, kThumbnailSize);
    expect([d.getUint8(0), d.getUint8(1), d.getUint8(2)], [255, 255, 255]);
  });
}
