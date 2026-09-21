import 'dart:math';

import 'package:image/image.dart' as img;

import 'types.dart';

/// 영역마다 다른 색을 입힌 검수용 이미지를 만든다.
///
/// 선은 검정, 배경은 연회색, 칠할 수 있는 영역은 각각 구분되는 색이다.
/// 영역이 잘못 이어져 있으면 두 곳이 같은 색으로 보이므로 한눈에 알 수 있다.
/// HSV 색상환을 황금각으로 돌며 색을 뽑아 인접 영역끼리 색이 붙지 않게 한다.
img.Image renderRegionPreview(RegionMap map, {int seed = 1}) {
  final im = img.Image(width: map.width, height: map.height, numChannels: 4);
  final palette = <int, List<int>>{};
  final ids = map.fillableRegionIds.toList()..sort();
  final jitter = Random(seed).nextDouble() * 360.0;

  for (var i = 0; i < ids.length; i++) {
    final hue = (jitter + i * 137.508) % 360.0; // 황금각
    palette[ids[i]] = _hsvToRgb(hue, 0.55, 0.95);
  }

  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final id = map.at(x, y);
      final List<int> rgb;
      if (id == kRegionLine) {
        rgb = const [0, 0, 0];
      } else if (id == kRegionBackground) {
        rgb = const [236, 236, 236];
      } else {
        rgb = palette[id] ?? const [255, 0, 255];
      }
      im.setPixelRgba(x, y, rgb[0], rgb[1], rgb[2], 255);
    }
  }
  return im;
}

List<int> _hsvToRgb(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - ((h / 60.0) % 2 - 1).abs());
  final m = v - c;
  double r, g, b;
  if (h < 60) {
    r = c; g = x; b = 0;
  } else if (h < 120) {
    r = x; g = c; b = 0;
  } else if (h < 180) {
    r = 0; g = c; b = x;
  } else if (h < 240) {
    r = 0; g = x; b = c;
  } else if (h < 300) {
    r = x; g = 0; b = c;
  } else {
    r = c; g = 0; b = x;
  }
  return [
    ((r + m) * 255).round().clamp(0, 255),
    ((g + m) * 255).round().clamp(0, 255),
    ((b + m) * 255).round().clamp(0, 255),
  ];
}
