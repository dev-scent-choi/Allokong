// 내장 도안용 합성 선화를 만든다. 실제 도안 에셋이 준비되면 이 파일은 지운다.
//
// 동심원 네 겹 — 품질 게이트(영역 4개 이상, 최소 지름 72px)를 통과하는
// 가장 단순한 모양이다.
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  const size = 1024;
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));

  void ink(int x, int y) {
    if (x >= 0 && y >= 0 && x < size && y < size) {
      im.setPixelRgba(x, y, 0, 0, 0, 255);
    }
  }

  // 반지름이 다른 원 네 개. 굵기 6px.
  for (final radius in [460, 340, 220, 100]) {
    for (var d = 0; d < 7200; d++) {
      final rad = d / 7200.0 * 6.283185307179586;
      final cx = 512 + radius * _cos(rad);
      final cy = 512 + radius * _sin(rad);
      for (var dy = -3; dy <= 3; dy++) {
        for (var dx = -3; dx <= 3; dx++) {
          ink(cx.round() + dx, cy.round() + dy);
        }
      }
    }
  }

  final out = args.isEmpty ? 'sample_lineart.png' : args[0];
  File(out).writeAsBytesSync(img.encodePng(im, level: 9));
  stdout.writeln('wrote $out (${size}x$size)');
}

double _cos(double r) {
  var s = 1.0, t = 1.0;
  for (var n = 1; n < 15; n++) {
    t *= -r * r / ((2 * n - 1) * (2 * n));
    s += t;
  }
  return s;
}

double _sin(double r) {
  var s = r, t = r;
  for (var n = 1; n < 15; n++) {
    t *= -r * r / ((2 * n) * (2 * n + 1));
    s += t;
  }
  return s;
}
