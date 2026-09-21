import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// 배경 안에 [count]개의 정사각형 방이 있는 맵을 만든다.
/// 각 방의 내부는 [inner]×[inner] 픽셀이다.
RegionMap _roomsMap({required int count, int inner = 10}) {
  const margin = 2;
  final cell = inner + 2; // 방 하나 + 테두리 선
  final w = margin * 2 + count * (cell + 1);
  final h = margin * 2 + cell;
  final rows = <String>[];
  for (var y = 0; y < h; y++) {
    final buf = StringBuffer();
    for (var x = 0; x < w; x++) {
      var ink = false;
      for (var k = 0; k < count; k++) {
        final x0 = margin + k * (cell + 1);
        final y0 = margin;
        final onV = (x == x0 || x == x0 + cell - 1) &&
            y >= y0 && y <= y0 + cell - 1;
        final onH = (y == y0 || y == y0 + cell - 1) &&
            x >= x0 && x <= x0 + cell - 1;
        if (onV || onH) ink = true;
      }
      buf.write(ink ? '#' : '.');
    }
    rows.add(buf.toString());
  }
  return cleanupRegions(labelRegions(maskFromRows(rows)), minArea: 1);
}

void main() {
  group('evaluateQuality', () {
    test('영역이 4개 미만이면 리젝트한다', () {
      final report = evaluateQuality(_roomsMap(count: 2));

      expect(report.passed, isFalse);
      expect(report.issues, contains(QualityIssue.tooFewRegions));
      expect(report.regionCount, 2);
    });

    test('영역이 120개를 넘으면 리젝트한다', () {
      final report = evaluateQuality(
        _roomsMap(count: 6),
        thresholds: const QualityThresholds(maxRegions: 5),
      );

      expect(report.passed, isFalse);
      expect(report.issues, contains(QualityIssue.tooManyRegions));
    });

    test('배경이 캔버스의 60% 미만이면 선이 샌다고 본다', () {
      // 선이 없는 맵. cleanupRegions가 전부 배경으로 만들면 배경 비율은 1.0.
      // 반대로 배경이 거의 없는 맵을 만들어 판정을 확인한다.
      final map = RegionMap.filled(10, 10, kRegionFirstFillable);
      for (var x = 0; x < 10; x++) {
        map.set(x, 0, kRegionBackground);
      }

      final report = evaluateQuality(map);

      expect(report.backgroundRatio, closeTo(0.10, 0.001));
      expect(report.issues, contains(QualityIssue.backgroundTooSmall));
    });

    test('손가락으로 누를 수 없는 영역이 있으면 표시한다', () {
      final report = evaluateQuality(
        _roomsMap(count: 5, inner: 4),
        thresholds: const QualityThresholds(
          minBackgroundRatio: 0.0,
          minTapDiameterPx: 20,
        ),
      );

      expect(report.smallestTapDiameter, lessThan(20));
      expect(report.issues, contains(QualityIssue.regionTooSmallToTap));
    });

    test('기준을 모두 만족하면 통과한다', () {
      final report = evaluateQuality(
        _roomsMap(count: 5, inner: 10),
        thresholds: const QualityThresholds(
          minBackgroundRatio: 0.0,
          minTapDiameterPx: 4,
        ),
      );

      expect(report.issues, isEmpty);
      expect(report.passed, isTrue);
      expect(report.regionCount, 5);
    });

    test('한국어 요약에 실패 사유가 담긴다', () {
      final report = evaluateQuality(_roomsMap(count: 2));

      expect(report.koreanSummary(), contains('영역'));
      expect(report.koreanSummary(), isNot(contains('null')));
    });
  });
}
