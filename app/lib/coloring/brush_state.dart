import 'dart:ui' as ui;
import 'dart:ui' show Offset;

import 'package:flutter/painting.dart' show Color;

/// 스펙 7.4 의 굵기. 캔버스(1024) 좌표 기준이다.
const double kCrayonWidth = 24;
const double kBrushWidth = 48;
const double kEraserWidth = 48;

enum BrushKind { crayon, brush, eraser }

/// 한 번의 획.
class Stroke {
  final BrushKind kind;

  /// `eraser` 일 때는 쓰이지 않는다 — 지우개는 색이 아니라 `BlendMode.clear` 다.
  final Color color;

  final double width;

  /// 획을 이루는 점들. **제자리에서 고치지 말 것.**
  ///
  /// `Stroke` 는 불변이다. `const Stroke(...)` 로 만들어지면 이 목록은 수정할 수
  /// 없고, 거기에 `add` 를 하면 손가락이 움직이는 도중에 터진다. 게다가
  /// `prefer_const_constructors` 린트가 켜져 있어서 분석기가 `const` 를 붙이라고
  /// 권한다 — 즉 분석기를 깨끗하게 유지하면 크래시가 생기는 구조였다.
  /// 점을 더할 때는 [withPoint] 로 새 획을 만든다.
  final List<Offset> points;

  const Stroke({
    required this.kind,
    required this.color,
    required this.width,
    required this.points,
  });

  /// 점 하나를 더한 새 획.
  ///
  /// 목록을 제자리에서 고치지 않는다 — 위 [points] 주석 참조.
  Stroke withPoint(Offset p) => Stroke(
        kind: kind,
        color: color,
        width: width,
        points: [...points, p],
      );

  /// [p] 가 이 획에 덮여 있는가.
  ///
  /// 픽셀을 읽지 않는다. 브러시 레이어는 우리가 직접 재생하므로 기하로 정확히
  /// 알 수 있고, 획 50개 × 점 100개라도 판정 한 번에 5천 번 거리 계산이라
  /// 탭 한 번에는 문제가 되지 않는다.
  bool covers(Offset p) {
    if (points.isEmpty) return false;
    final r = width / 2;
    if (points.length == 1) return (points.first - p).distance <= r;
    for (var i = 0; i < points.length - 1; i++) {
      if (_distanceToSegment(p, points[i], points[i + 1]) <= r) return true;
    }
    return false;
  }
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final abx = b.dx - a.dx;
  final aby = b.dy - a.dy;
  final len2 = abx * abx + aby * aby;
  if (len2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2).clamp(0.0, 1.0);
  return (p - Offset(a.dx + abx * t, a.dy + aby * t)).distance;
}

/// 브러시 레이어 상태.
///
/// 획을 오프스크린 이미지에 누적하지 않는다. `ui.Image` 는 불변이라 덧그리려면
/// 매번 새 이미지를 만들어야 하고, 1024² 면 한 장에 4MB 다. 대신 매 프레임
/// 목록을 재생한다 — 실측 2ms — 그러면 되돌리기 리플레이도 공짜로 따라온다.
class BrushState {
  /// 이전 세션에서 구운 `brush.png`. 없으면 null.
  ui.Image? base;

  /// 이번 세션에 그은 획들.
  final List<Stroke> strokes = [];

  /// 지금 손가락이 그리고 있는 중인 획. 아직 명령으로 쌓이지 않았다.
  Stroke? live;

  int _revision = 0;

  /// 마지막 저장 이후 브러시가 바뀌었는지 판단하는 값.
  int get revision => _revision;

  bool get isEmpty => base == null && strokes.isEmpty && live == null;

  void push(Stroke s) {
    strokes.add(s);
    _revision++;
  }

  void removeStroke(Stroke s) {
    strokes.remove(s);
    _revision++;
  }

  /// [p] 를 이번 세션의 **잉크** 획이 덮고 있는가.
  ///
  /// 지우개 획은 제외한다 — 잉크를 없앤 자국이지 잉크가 아니다. 나중 지우개가
  /// 앞선 잉크를 지웠는지까지 순서대로 되짚지는 않는다. 이 판정의 용도(채움을
  /// 벗길지 말지)에 그 정밀도는 필요 없다.
  bool hasInkAt(Offset p) {
    for (final s in strokes) {
      if (s.kind != BrushKind.eraser && s.covers(p)) return true;
    }
    return false;
  }

  void clear() {
    strokes.clear();
    live = null;
    base = null;
    _revision++;
  }
}
