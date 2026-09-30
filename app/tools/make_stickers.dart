// 스티커 그림 10장을 굽는다. 디자이너가 없으므로 도형을 수식으로 그린다.
//
// 실행: cd app && dart run tools/make_stickers.dart
//
// 라이브러리의 도형 그리기 API 를 쓰지 않고 픽셀마다 "안인가"를 판정한다.
// API 이름을 잘못 짚을 위험이 없고, 도형을 늘리기도 쉽다.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int kSize = 256;

/// 정규화 좌표(-1..1)에서 도형 안인지 판정한다.
typedef Shape = bool Function(double x, double y);

double _r(double x, double y) => math.sqrt(x * x + y * y);
double _theta(double x, double y) => math.atan2(y, x);

class _Sticker {
  final Shape shape;
  final int fill;
  const _Sticker(this.shape, this.fill);
}

final Map<String, _Sticker> _stickers = {
  'star-01': _Sticker((x, y) {
    final t = _theta(x, y) + math.pi / 2;
    final k = 5 * t / (2 * math.pi);
    final f = (k - k.floorToDouble()) * 2 - 1;
    return _r(x, y) <= 0.42 + 0.46 * (1 - f.abs());
  }, 0xF1BD45),
  'heart-01': _Sticker((x, y) {
    final px = x * 1.35;
    final py = -y * 1.35 + 0.25;
    final a = px * px + py * py - 1;
    return a * a * a - px * px * py * py * py <= 0;
  }, 0xEF7586),
  'flower-01': _Sticker(
    (x, y) => _r(x, y) <= 0.5 + 0.38 * math.cos(6 * _theta(x, y)).abs(),
    0x9E82CF,
  ),
  'dot-01': _Sticker((x, y) => _r(x, y) <= 0.85, 0x6CAEE0),
  'diamond-01': _Sticker((x, y) => x.abs() + y.abs() <= 0.9, 0x63B98B),
  'triangle-01': _Sticker(
    (x, y) => y <= 0.72 && (y + 0.72) >= 1.75 * x.abs(),
    0xEF8A45,
  ),
  'moon-01': _Sticker(
    (x, y) => _r(x, y) <= 0.85 && _r(x - 0.42, y) > 0.7,
    0xF1BD45,
  ),
  'ring-01': _Sticker(
    (x, y) => _r(x, y) <= 0.85 && _r(x, y) >= 0.48,
    0xEF7586,
  ),
  'cross-01': _Sticker(
    (x, y) => (x.abs() <= 0.28 && y.abs() <= 0.85) ||
        (y.abs() <= 0.28 && x.abs() <= 0.85),
    0x6CAEE0,
  ),
  'cloud-01': _Sticker(
    (x, y) =>
        _r(x + 0.38, y - 0.12) <= 0.4 ||
        _r(x - 0.38, y - 0.12) <= 0.4 ||
        _r(x, y - 0.3) <= 0.5 ||
        (y >= -0.12 && y <= 0.3 && x.abs() <= 0.45),
    0xAED2EE,
  ),
};

int _darken(int rgb) {
  final r = (((rgb >> 16) & 0xFF) * 0.55).round();
  final g = (((rgb >> 8) & 0xFF) * 0.55).round();
  final b = ((rgb & 0xFF) * 0.55).round();
  return (r << 16) | (g << 8) | b;
}

void main() {
  final dir = Directory('assets/stickers');
  dir.createSync(recursive: true);

  for (final entry in _stickers.entries) {
    final s = entry.value;
    final outline = _darken(s.fill);
    final im = img.Image(width: kSize, height: kSize, numChannels: 4);

    for (var py = 0; py < kSize; py++) {
      for (var px = 0; px < kSize; px++) {
        final nx = (px + 0.5) / kSize * 2 - 1;
        final ny = (py + 0.5) / kSize * 2 - 1;
        if (!s.shape(nx, ny)) continue;
        // 살짝 키운 좌표에서 벗어나면 가장자리다 = 테두리
        final c = s.shape(nx * 1.1, ny * 1.1) ? s.fill : outline;
        im.setPixelRgba(px, py, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, 255);
      }
    }

    final path = '${dir.path}/${entry.key}.png';
    File(path).writeAsBytesSync(img.encodePng(im));
    stdout.writeln('wrote $path');
  }
}
