import 'dart:collection';
import 'dart:typed_data';

import 'types.dart';

/// 도안이 아이에게 쓸 만한지 판정할 때 걸리는 항목.
enum QualityIssue {
  /// 영역이 너무 적다. 라벨링이 실패했거나 도안이 지나치게 단순하다.
  tooFewRegions,

  /// 영역이 너무 많다. 선이 지저분해 아이가 칠하기 어렵다.
  tooManyRegions,

  /// 배경이 너무 좁다. 선이 끊겨 색이 새고 있다는 신호다.
  backgroundTooSmall,

  /// 손가락으로 누를 수 없을 만큼 작은 영역이 있다.
  regionTooSmallToTap,
}

/// 품질 게이트 기준값.
///
/// [minTapDiameterPx]는 1024px 캔버스 기준 픽셀 수다. 기본값 72는 폰에서
/// 캔버스가 약 340dp로 표시될 때의 24dp에 해당한다. UI 버튼의 64dp 최소
/// 터치 타겟과는 다른 기준이다 — 도안 디테일에 64dp를 적용하면 공룡 발톱
/// 같은 정상적인 영역이 전부 병합된다.
class QualityThresholds {
  final int minRegions;
  final int maxRegions;
  final double minBackgroundRatio;
  final int minTapDiameterPx;

  const QualityThresholds({
    this.minRegions = 4,
    this.maxRegions = 120,
    this.minBackgroundRatio = 0.60,
    this.minTapDiameterPx = 72,
  });
}

/// 품질 게이트 판정 결과.
class QualityReport {
  final int regionCount;
  final double backgroundRatio;
  final int smallestTapDiameter;
  final List<QualityIssue> issues;

  const QualityReport({
    required this.regionCount,
    required this.backgroundRatio,
    required this.smallestTapDiameter,
    required this.issues,
  });

  bool get passed => issues.isEmpty;

  /// 사람이 읽을 판정 요약.
  String koreanSummary() {
    if (issues.isEmpty) {
      return '통과 — 영역 $regionCount개, 배경 '
          '${(backgroundRatio * 100).toStringAsFixed(1)}%, '
          '최소 영역 지름 ${smallestTapDiameter}px';
    }
    final reasons = issues.map((i) {
      switch (i) {
        case QualityIssue.tooFewRegions:
          return '칠할 수 있는 영역이 $regionCount개뿐입니다';
        case QualityIssue.tooManyRegions:
          return '영역이 $regionCount개로 너무 많습니다';
        case QualityIssue.backgroundTooSmall:
          return '배경이 ${(backgroundRatio * 100).toStringAsFixed(1)}%뿐입니다 '
              '(선이 끊겨 색이 새고 있을 수 있습니다)';
        case QualityIssue.regionTooSmallToTap:
          return '가장 작은 영역의 지름이 ${smallestTapDiameter}px로 '
              '손가락으로 누르기 어렵습니다';
      }
    });
    return '리젝트 — ${reasons.join(' / ')}';
  }
}

/// 영역 맵이 품질 기준을 만족하는지 판정한다.
QualityReport evaluateQuality(
  RegionMap map, {
  QualityThresholds thresholds = const QualityThresholds(),
}) {
  final areas = map.areaByRegion();
  final total = map.width * map.height;
  final regionCount = map.fillableRegionCount;
  final backgroundRatio = (areas[kRegionBackground] ?? 0) / total;
  final smallest = _smallestInscribedDiameter(map);

  final issues = <QualityIssue>[];
  if (regionCount < thresholds.minRegions) {
    issues.add(QualityIssue.tooFewRegions);
  }
  if (regionCount > thresholds.maxRegions) {
    issues.add(QualityIssue.tooManyRegions);
  }
  if (backgroundRatio < thresholds.minBackgroundRatio) {
    issues.add(QualityIssue.backgroundTooSmall);
  }
  if (regionCount > 0 && smallest < thresholds.minTapDiameterPx) {
    issues.add(QualityIssue.regionTooSmallToTap);
  }

  return QualityReport(
    regionCount: regionCount,
    backgroundRatio: backgroundRatio,
    smallestTapDiameter: smallest,
    issues: issues,
  );
}

/// 칠할 수 있는 영역들의 내접원 지름 중 가장 작은 값.
///
/// 영역 경계에서 시작하는 8방 BFS로 체비셰프 거리 변환을 구한다. 체비셰프
/// 거리의 최대값은 내접 정사각형의 반지름이므로, 지름은 그 2배 + 1이다.
/// 원이 아니라 정사각형이지만 판정 목적에는 충분하다.
///
/// 외접원이 아니라 내접원을 쓰는 이유는, 가늘고 긴 영역은 외접원이 커도
/// 손가락으로 누를 수 없기 때문이다.
int _smallestInscribedDiameter(RegionMap map) {
  final w = map.width;
  final h = map.height;
  final dist = Int32List(w * h)..fillRange(0, w * h, -1);
  final queue = Queue<int>();

  // 자기 영역이 아닌 이웃을 가졌거나 캔버스 경계에 있는 픽셀이 거리 0이다.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final id = map.ids[i];
      if (id < kRegionFirstFillable) continue;
      var isEdge = x == 0 || y == 0 || x == w - 1 || y == h - 1;
      if (!isEdge) {
        outer:
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (map.ids[(y + dy) * w + (x + dx)] != id) {
              isEdge = true;
              break outer;
            }
          }
        }
      }
      if (isEdge) {
        dist[i] = 0;
        queue.add(i);
      }
    }
  }

  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    final x = i % w;
    final y = i ~/ w;
    final id = map.ids[i];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final xx = x + dx;
        final yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        final j = yy * w + xx;
        if (map.ids[j] != id) continue;
        if (dist[j] != -1) continue;
        dist[j] = dist[i] + 1;
        queue.add(j);
      }
    }
  }

  final maxPerRegion = <int, int>{};
  for (var i = 0; i < w * h; i++) {
    final id = map.ids[i];
    if (id < kRegionFirstFillable) continue;
    final d = dist[i];
    if (d > (maxPerRegion[id] ?? -1)) maxPerRegion[id] = d;
  }
  if (maxPerRegion.isEmpty) return 0;

  var smallest = 1 << 30;
  for (final radius in maxPerRegion.values) {
    final diameter = radius * 2 + 1;
    if (diameter < smallest) smallest = diameter;
  }
  return smallest;
}
