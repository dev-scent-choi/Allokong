import 'distance_field.dart';
import 'types.dart';

/// 도안이 아이에게 쓸 만한지 판정할 때 걸리는 항목.
enum QualityIssue {
  /// 영역이 너무 적다. 라벨링이 실패했거나 도안이 지나치게 단순하다.
  tooFewRegions,

  /// 영역이 너무 많다. 선이 지저분해 아이가 칠하기 어렵다.
  tooManyRegions,

  /// 손가락으로 누를 수 없을 만큼 작은 영역이 있다.
  regionTooSmallToTap,
}

/// 품질 게이트 기준값.
///
/// [minTapDiameterPx]는 1024px 캔버스 기준 픽셀 수다. 기본값 72는 폰에서
/// 캔버스가 약 340dp로 표시될 때의 24dp에 해당한다. UI 버튼의 64dp 최소
/// 터치 타겟과는 다른 기준이다 — 도안 디테일에 64dp를 적용하면 공룡 발톱
/// 같은 정상적인 영역이 전부 병합된다.
///
/// 배경 비율은 계측값으로만 보고하고 판정에는 쓰지 않는다. 누수가 나면 내부가
/// 바깥과 이어져 통째로 BACKGROUND 가 되므로 배경은 오히려 **커진다** —
/// "배경이 작으면 누수"는 방향이 반대인 규칙이었고, 지면을 꽉 채운 정상 도안을
/// 거부했다. 누수 판정은 tooFewRegions 가 맡는다.
class QualityThresholds {
  final int minRegions;
  final int maxRegions;
  final int minTapDiameterPx;

  const QualityThresholds({
    this.minRegions = 4,
    this.maxRegions = 120,
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
        case QualityIssue.regionTooSmallToTap:
          return '가장 작은 영역의 지름이 ${smallestTapDiameter}px로 '
              '손가락으로 누르기 어렵습니다';
      }
    });
    return '리젝트 — ${reasons.join(' / ')} '
        '(영역 $regionCount개, 배경 ${(backgroundRatio * 100).toStringAsFixed(1)}%, '
        '최소 영역 지름 ${smallestTapDiameter}px)';
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
  final smallest = smallestInscribedDiameter(map);

  final issues = <QualityIssue>[];
  if (regionCount < thresholds.minRegions) {
    issues.add(QualityIssue.tooFewRegions);
  }
  if (regionCount > thresholds.maxRegions) {
    issues.add(QualityIssue.tooManyRegions);
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
