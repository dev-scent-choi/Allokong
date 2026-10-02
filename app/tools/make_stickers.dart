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

/// 각도별 반지름을 삼각파로 보간하면(이전 시도) 극좌표의 선형 보간이
/// 직교좌표에서는 곡선이 되어 뾰족한 꼭짓점 대신 둥근 꽃잎이 된다. 진짜
/// 별 모양은 바깥 꼭짓점과 안쪽 골을 **직선**으로 잇는다 — 그 직선을
/// 극좌표 방정식 r(θ) = C / (A cosθ + B sinθ) 로 직접 계산한다
/// (두 점을 지나는 직선의 일반형 Ax+By=C 를 극좌표로 바꾼 것).
double _starRadius(
  double theta, {
  required int points,
  required double outerR,
  required double innerR,
}) {
  final step = math.pi / points; // 바깥·안쪽 꼭짓점이 번갈아 나오는 간격
  const twoPi = 2 * math.pi;
  final t = theta - twoPi * (theta / twoPi).floorToDouble();
  final segment = (t / step).floor();
  final a0 = segment * step;
  final a1 = a0 + step;
  final r0 = segment.isEven ? outerR : innerR;
  final r1 = segment.isEven ? innerR : outerR;
  final x0 = r0 * math.cos(a0), y0 = r0 * math.sin(a0);
  final x1 = r1 * math.cos(a1), y1 = r1 * math.sin(a1);
  final a = y0 - y1;
  final b = x1 - x0;
  final c = x1 * y0 - y1 * x0;
  final denom = a * math.cos(t) + b * math.sin(t);
  if (denom == 0) return outerR;
  return c / denom;
}

class _Sticker {
  final Shape shape;
  final int fill;
  const _Sticker(this.shape, this.fill);
}

final Map<String, _Sticker> _stickers = {
  'star-01': _Sticker((x, y) {
    final theta = _theta(x, y) + math.pi / 2; // 꼭짓점 하나가 위를 보게
    final edge = _starRadius(theta, points: 5, outerR: 0.95, innerR: 0.40);
    return _r(x, y) <= edge;
  }, 0xF1BD45),
  'heart-01': _Sticker((x, y) {
    final px = x * 1.35;
    final py = -y * 1.35 + 0.25;
    final a = px * px + py * py - 1;
    return a * a * a - px * px * py * py * py <= 0;
  }, 0xEF7586),
  // cos(6θ) 의 "6" 을 보고 꽃잎 여섯 장을 떠올리기 쉽지만, 밖에 .abs() 를
  // 씌워 극좌표 장미 곡선의 음의 로브를 양의 로브로 접으면 로브 수가 두
  // 배가 된다 — 실제로는 **12 장**이다. star-01 과 두 칸 떨어져 나란히
  // 있어서, 둘이 비슷해 보이면 글을 못 읽는 아이에게는 같은 신호가 된다.
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
