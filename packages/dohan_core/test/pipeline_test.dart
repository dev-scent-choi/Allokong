import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// 흰 배경 위에 검은 테두리 사각형을 그린 이미지.
/// [gapWidth]만큼 테두리 위쪽을 비워 "끊긴 선"을 만든다.
img.Image _boxImage({
  int size = 128,
  int inset = 24,
  int stroke = 3,
  int gapWidth = 0,
}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
  final lo = inset;
  final hi = size - inset - 1;
  final gapFrom = size ~/ 2 - gapWidth ~/ 2;
  final gapTo = gapFrom + gapWidth;

  void ink(int x, int y) {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    im.setPixelRgba(x, y, 0, 0, 0, 255);
  }

  for (var t = 0; t < stroke; t++) {
    for (var x = lo; x <= hi; x++) {
      if (!(x >= gapFrom && x < gapTo)) ink(x, lo + t); // 위 (여기에 틈)
      ink(x, hi - t); // 아래
    }
    for (var y = lo; y <= hi; y++) {
      ink(lo + t, y);
      ink(hi - t, y);
    }
  }
  return im;
}

void main() {
  const lenient = QualityThresholds(
    minRegions: 1,
    maxRegions: 120,
    minTapDiameterPx: 4,
  );

  group('runPipeline', () {
    test('닫힌 사각형은 안과 밖이 분리된다', () {
      final result = runPipeline(
        _boxImage(),
        options: const PipelineOptions(thresholds: lenient),
      );

      expect(result.regions.fillableRegionCount, 1,
          reason: '바깥은 배경이 되고 내부 하나만 칠할 수 있어야 한다');
      expect(result.regions.at(64, 64),
          greaterThanOrEqualTo(kRegionFirstFillable));
      expect(result.regions.at(1, 1), kRegionBackground);
    });

    test('선 보정을 끄면 끊긴 사각형에서 색이 샌다 (회귀 기준선)', () {
      final result = runPipeline(
        _boxImage(gapWidth: 4),
        options: const PipelineOptions(
          closeRadius: 0,
          thresholds: lenient,
        ),
      );

      // 틈으로 안과 밖이 이어져 하나의 연결요소가 되고, 그것이 캔버스
      // 테두리에 닿으므로 전부 배경이 된다 = 칠할 곳이 없다.
      expect(result.regions.fillableRegionCount, 0,
          reason: '보정을 끄면 내부가 배경에 삼켜진다');
      expect(result.regions.at(64, 64), kRegionBackground);
    });

    test('선 보정을 켜면 끊긴 사각형도 내부가 살아난다 (누수 회귀 테스트)', () {
      final result = runPipeline(
        _boxImage(gapWidth: 4),
        options: const PipelineOptions(
          closeRadius: 3,
          thresholds: lenient,
        ),
      );

      expect(result.regions.fillableRegionCount, 1,
          reason: '틈이 메워져 내부가 독립 영역이 되어야 한다');
      expect(result.regions.at(64, 64),
          greaterThanOrEqualTo(kRegionFirstFillable),
          reason: '사각형 한가운데는 칠할 수 있어야 한다');
      expect(result.regions.at(1, 1), kRegionBackground,
          reason: '바깥은 배경이어야 한다');
    });

    test('누수가 나면 품질 게이트가 잡아낸다', () {
      final result = runPipeline(
        _boxImage(gapWidth: 4),
        options: const PipelineOptions(closeRadius: 0),
      );

      expect(result.quality.passed, isFalse);
      expect(result.quality.issues, contains(QualityIssue.tooFewRegions));
    });

    test('결과에 이진 마스크와 품질 리포트가 함께 담긴다', () {
      final result = runPipeline(
        _boxImage(),
        options: const PipelineOptions(thresholds: lenient),
      );

      expect(result.ink.width, 128);
      expect(result.ink.inkCount, greaterThan(0));
      expect(result.quality.regionCount, result.regions.fillableRegionCount);
    });
  });
}
