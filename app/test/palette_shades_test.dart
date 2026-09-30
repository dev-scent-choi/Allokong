import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/ui/palette_shades.dart';

/// 스펙 7.3 의 공식. 표가 이 공식에서 나왔다는 것을 잠근다.
Color lighter(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness(h.lightness + (1 - h.lightness) * 0.45).toColor();
}

Color darker(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness * 0.62).clamp(0.0, 1.0)).toColor();
}

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('세 단계 모두 여덟 색이다', () {
    for (final shade in Shade.values) {
      expect(paletteShades[shade], hasLength(8), reason: '$shade');
    }
  });

  test('기본 단계는 상위 스펙 9장의 값 그대로다', () {
    expect(paletteShades[Shade.base], const [
      Color(0xFFEF7586),
      Color(0xFFF1BD45),
      Color(0xFFEF8A45),
      Color(0xFF6CAEE0),
      Color(0xFF63B98B),
      Color(0xFF9E82CF),
      Color(0xFF795548),
      Color(0xFFF5F5F5),
    ]);
  });

  test('밝은 단계가 공식과 일치한다', () {
    final base = paletteShades[Shade.base]!;
    final light = paletteShades[Shade.light]!;
    for (var i = 0; i < 8; i++) {
      expect(light[i], lighter(base[i]),
          reason: '$i 번째 색이 공식과 어긋난다 — 표를 고치거나 공식을 고쳐야 한다');
    }
  });

  test('어두운 단계가 공식과 일치한다', () {
    final base = paletteShades[Shade.base]!;
    final dark = paletteShades[Shade.dark]!;
    for (var i = 0; i < 8; i++) {
      expect(dark[i], darker(base[i]), reason: '$i 번째 색이 공식과 어긋난다');
    }
  });

  test('명도를 누르면 밝게 → 기본 → 어둡게 로 돌고 되돌아온다', () {
    expect(Shade.light.next, Shade.base);
    expect(Shade.base.next, Shade.dark);
    expect(Shade.dark.next, Shade.light);
  });

  test('테두리색이 24색 전부에서 배경과 구분된다', () {
    // 계획 2 가 잡은 "흰 크레용이 안 보인다"(1.06:1)의 재발을 막는다.
    // 스와치 안쪽 색이 배경에 묻혀도 테두리는 항상 보여야 한다.
    const page = Color(0xFFFCFCF8);
    const border = Color(0xFF757D75);
    expect(contrast(border, page), greaterThanOrEqualTo(3.0));
  });

  test('같은 단계 안에서 여덟 색이 서로 다르다', () {
    for (final shade in Shade.values) {
      final seen = paletteShades[shade]!.map((c) => c.toARGB32()).toSet();
      expect(seen, hasLength(8), reason: '$shade 에 중복된 색이 있다');
    }
  });
}
