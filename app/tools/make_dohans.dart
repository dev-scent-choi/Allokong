// 내장 도안 12장의 선화를 그린다. 흰 바탕에 검은 윤곽선만 있고
// 닫힌 영역이 색칠할 자리가 된다. dohan_cli 가 그 영역을 라벨링한다.
//
// 실행:  cd app && C:/src/flutter/bin/dart run tools/make_dohans.dart <출력디렉터리>
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int kSize = 1024;
const int kInkRadius = 3; // 굵기 7px

class Pen {
  final img.Image im;
  Pen(this.im);

  void dot(double x, double y) {
    final cx = x.round(), cy = y.round();
    for (var dy = -kInkRadius; dy <= kInkRadius; dy++) {
      for (var dx = -kInkRadius; dx <= kInkRadius; dx++) {
        final px = cx + dx, py = cy + dy;
        if (px >= 0 && py >= 0 && px < kSize && py < kSize) {
          im.setPixelRgba(px, py, 0, 0, 0, 255);
        }
      }
    }
  }

  void line(double x1, double y1, double x2, double y2) {
    final n = math.max((x2 - x1).abs(), (y2 - y1).abs()).ceil() * 2 + 1;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      dot(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
  }

  void poly(List<double> pts, {bool close = true}) {
    for (var i = 0; i + 3 < pts.length; i += 2) {
      line(pts[i], pts[i + 1], pts[i + 2], pts[i + 3]);
    }
    if (close) {
      line(pts[pts.length - 2], pts[pts.length - 1], pts[0], pts[1]);
    }
  }

  void arc(double cx, double cy, double rx, double ry, double a0, double a1) {
    final steps = (math.max(rx, ry) * (a1 - a0).abs()).ceil() * 2 + 8;
    for (var i = 0; i <= steps; i++) {
      final a = a0 + (a1 - a0) * i / steps;
      dot(cx + rx * math.cos(a), cy + ry * math.sin(a));
    }
  }

  void ellipse(double cx, double cy, double rx, double ry) =>
      arc(cx, cy, rx, ry, 0, 2 * math.pi);

  void circle(double cx, double cy, double r) => ellipse(cx, cy, r, r);

  void rect(double l, double t, double r, double b) =>
      poly([l, t, r, t, r, b, l, b]);

  /// 다각형 [shape] 안쪽만 칠하는 분할선.
  ///
  /// 분할선은 실루엣을 확실히 가로지르도록 일부러 바깥에서 시작해 바깥에서
  /// 끝낸다 — 안에서 끝나면 아무것도 나누지 못한다. 그 꼬리를 그대로 두면
  /// 허공에 뜬 선이 남아, 아이가 칠하려 들지만 아무 일도 일어나지 않는다.
  void cut(List<double> shape, double x1, double y1, double x2, double y2) {
    final n = math.max((x2 - x1).abs(), (y2 - y1).abs()).ceil() * 2 + 1;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final x = x1 + (x2 - x1) * t;
      final y = y1 + (y2 - y1) * t;
      if (_inside(shape, x, y)) dot(x, y);
    }
  }

  /// 짝수-홀수 규칙(광선 투사)으로 점이 다각형 안인지 본다.
  static bool _inside(List<double> shape, double x, double y) {
    var inside = false;
    final n = shape.length ~/ 2;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = shape[i * 2], yi = shape[i * 2 + 1];
      final xj = shape[j * 2], yj = shape[j * 2 + 1];
      if ((yi > y) != (yj > y) &&
          x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }
}

typedef Draw = void Function(Pen p);

/// 도안 하나의 정의.
class Spec {
  final String id;
  final String title;
  final String category;
  final int difficulty;
  final Draw draw;
  const Spec(this.id, this.title, this.category, this.difficulty, this.draw);
}

const tau = 2 * math.pi;

final specs = <Spec>[
  // 그리는 규칙 — 실측으로 얻었다(스펙 9.1):
  //  1) 실루엣은 **닫힌 외곽선 하나**. 윤곽선끼리 교차시키지 않는다 —
  //     교차점마다 얇은 조각이 생겨 최소 지름 72px 기준에 걸린다.
  //  2) 내부를 나눌 때는 실루엣을 **완전히 가로지르는** 선을 쓴다.
  //     안에서 끝나는 선은 아무것도 나누지 못한다.
  //  3) 장식(눈·배)은 한 영역 **안에 완전히** 들어가고 지름 100px 이상.

  // ── 동물 ──────────────────────────────────────────────
  Spec('animal-cat-01', '고양이', 'animal', 1, (p) {
    // 귀까지 한 다각형으로 그린다. 귀를 따로 그려 머리와 교차시키면
    // 교차점에 33px 짜리 조각이 생긴다(실측).
    p.poly([
      230, 430, 270, 160, 430, 330, 594, 330, 754, 160, 794, 430,
      760, 700, 600, 840, 424, 840, 264, 700,
    ]);
    p.circle(400, 480, 70); // 왼쪽 눈
    p.circle(624, 480, 70); // 오른쪽 눈
    p.circle(512, 660, 70); // 코
  }),
  Spec('animal-fish-01', '물고기', 'animal', 1, (p) {
    const body = <double>[
      170, 450, 430, 300, 720, 330, 960, 250, 830, 512, 960, 774,
      720, 694, 430, 724, 170, 575,
    ];
    p.poly(body);
    p.cut(body, 470, 240, 470, 790); // 머리 경계
    p.cut(body, 700, 230, 700, 800); // 꼬리 경계
    p.circle(300, 505, 62);     // 눈
  }),
  Spec('animal-bird-01', '새', 'animal', 1, (p) {
    const body = <double>[
      90, 360, 250, 300, 400, 180, 560, 300, 820, 620, 700, 860,
      420, 880, 250, 700, 250, 430,
    ];
    p.poly(body);
    p.cut(body, 170, 530, 650, 265); // 머리 경계
    p.cut(body, 200, 600, 870, 690); // 날개 경계
    p.circle(345, 355, 60);     // 눈
  }),

  // ── 자동차 ────────────────────────────────────────────
  Spec('car-sedan-01', '승용차', 'car', 1, (p) {
    const roof = <double>[260, 520, 360, 330, 680, 330, 780, 520];
    p.rect(120, 520, 904, 760);
    p.poly(roof);
    p.cut(roof, 512, 300, 512, 540); // 창 가운데 기둥
    p.circle(290, 760, 110);
    p.circle(734, 760, 110);
  }),
  Spec('car-truck-01', '트럭', 'car', 2, (p) {
    // 짐칸과 운전석을 각각의 사각형으로 그리면 맞닿은 변에 41px 짜리
    // 조각이 생긴다(실측). 하나의 다각형으로 그리고 선으로 나눈다.
    const body = <double>[
      110, 430, 480, 430, 480, 540, 910, 540, 910, 740, 110, 740,
    ];
    p.poly(body);
    p.cut(body, 480, 400, 480, 780); // 짐칸 / 운전석
    p.circle(295, 740, 110);
    p.circle(695, 740, 110);
  }),
  Spec('car-bus-01', '버스', 'car', 2, (p) {
    const body = <double>[100, 330, 924, 330, 924, 760, 100, 760];
    p.poly(body);
    p.cut(body, 80, 470, 944, 470);  // 창 윗줄
    p.cut(body, 374, 300, 374, 470); // 창 칸막이 1
    p.cut(body, 650, 300, 650, 470); // 창 칸막이 2
    p.circle(280, 760, 110);
    p.circle(744, 760, 110);
  }),

  // ── 공룡 ──────────────────────────────────────────────
  Spec('dino-stego-01', '스테고사우루스', 'dinosaur', 2, (p) {
    const body = <double>[
      90, 430, 200, 340, 330, 400, 420, 230, 510, 400, 600, 230,
      690, 400, 900, 380, 990, 520, 900, 660, 620, 790, 330, 790,
      150, 620,
    ];
    p.poly(body);
    p.cut(body, 300, 300, 300, 860); // 머리 경계
    p.cut(body, 720, 300, 720, 860); // 꼬리 경계
    p.circle(480, 620, 110);    // 배
  }),
  Spec('dino-trex-01', '티라노사우루스', 'dinosaur', 3, (p) {
    const body = <double>[
      60, 520, 230, 430, 430, 330, 640, 250, 780, 190, 960, 300,
      940, 410, 760, 440, 680, 530, 560, 740, 330, 790, 180, 650,
    ];
    p.poly(body);
    p.cut(body, 660, 160, 660, 600); // 머리 경계
    p.cut(body, 260, 380, 300, 830); // 꼬리 경계
    p.circle(820, 310, 60);     // 눈
    p.circle(430, 580, 115);    // 배
  }),
  Spec('dino-bronto-01', '브라키오사우루스', 'dinosaur', 2, (p) {
    const body = <double>[
      50, 700, 220, 600, 420, 500, 580, 470, 600, 220, 700, 130,
      880, 180, 850, 330, 760, 300, 770, 520, 870, 700, 620, 840,
      330, 850, 150, 810,
    ];
    p.poly(body);
    p.cut(body, 480, 450, 920, 600); // 목 / 몸통
    p.cut(body, 540, 380, 900, 380); // 목 가로 분할
    p.circle(400, 690, 120);    // 배
  }),

  // ── 모양 ──────────────────────────────────────────────
  Spec('flower-01', '동그라미 꽃', 'shape', 1, (p) {
    for (final r in [460.0, 340.0, 220.0, 100.0]) {
      p.circle(512, 512, r);
    }
  }),
  Spec('shape-star-01', '별', 'shape', 1, (p) {
    const inner = 110.0;
    final tips = <double>[];
    final pts = <double>[];
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? 440.0 : 200.0;
      final x = 512 + r * math.cos(a);
      final y = 512 + r * math.sin(a);
      pts..add(x)..add(y);
      if (i.isEven) tips..add(x)..add(y);
    }
    p.poly(pts);
    p.circle(512, 512, inner);
    // 가운데 원에서 각 꼭짓점까지 — 원 테두리도 잉크라서 쐐기가 닫힌다.
    for (var i = 0; i + 1 < tips.length; i += 2) {
      final a = math.atan2(tips[i + 1] - 512, tips[i] - 512);
      p.line(512 + inner * math.cos(a), 512 + inner * math.sin(a),
          tips[i], tips[i + 1]);
    }
  }),
  Spec('shape-house-01', '집', 'shape', 1, (p) {
    p.poly([200, 480, 150, 480, 512, 170, 874, 480, 824, 480, 824, 880, 200, 880]);
    p.line(200, 480, 824, 480); // 지붕 / 몸체
    p.rect(300, 580, 470, 750); // 창문
    p.rect(590, 620, 750, 880); // 문
  }),
];

void main(List<String> args) {
  final dir = args.isEmpty ? '.' : args[0];
  Directory(dir).createSync(recursive: true);
  for (final s in specs) {
    final im = img.Image(width: kSize, height: kSize, numChannels: 4);
    img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
    s.draw(Pen(im));
    File('$dir/${s.id}.png').writeAsBytesSync(img.encodePng(im, level: 9));
  }
  stdout.writeln('wrote ${specs.length} line arts to $dir');
}
