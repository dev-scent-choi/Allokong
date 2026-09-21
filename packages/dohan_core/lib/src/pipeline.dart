import 'package:image/image.dart' as img;

import 'binarize.dart';
import 'cleanup.dart';
import 'label_regions.dart';
import 'morphology.dart';
import 'quality_gate.dart';
import 'types.dart';

/// 파이프라인 단계별 조절값.
class PipelineOptions {
  final int binarizeWindow;
  final int binarizeOffset;

  /// 선 끊김 보정 반지름. null이면 선 두께에서 추정한다.
  /// 0을 주면 보정을 건너뛴다 — 테스트에서 누수 기준선을 만들 때만 쓴다.
  final int? closeRadius;

  final int minRegionArea;
  final int neighborSearchRadius;
  final QualityThresholds thresholds;

  const PipelineOptions({
    this.binarizeWindow = 31,
    this.binarizeOffset = 10,
    this.closeRadius,
    this.minRegionArea = 24,
    this.neighborSearchRadius = 3,
    this.thresholds = const QualityThresholds(),
  });
}

/// 파이프라인 산출물.
class PipelineResult {
  /// 보정까지 마친 선 마스크. 선화 렌더링에 쓴다.
  final BinaryMask ink;

  /// 칠할 수 있는 영역이 분리된 인덱스 맵.
  final RegionMap regions;

  final QualityReport quality;

  const PipelineResult({
    required this.ink,
    required this.regions,
    required this.quality,
  });
}

/// 선화 이미지를 도안으로 변환한다.
///
/// 이진화 → 선 끊김 보정 → 연결요소 라벨링 → 영역 정리 → 품질 판정 순으로
/// 진행한다. 빌드 타임 배치 생성과 온디바이스 사진 변환이 이 함수를 공유한다.
PipelineResult runPipeline(
  img.Image source, {
  PipelineOptions options = const PipelineOptions(),
}) {
  final binary = binarize(
    source,
    window: options.binarizeWindow,
    offset: options.binarizeOffset,
  );

  final closed = options.closeRadius == 0
      ? binary
      : closeLines(binary, radius: options.closeRadius);

  final labeled = labelRegions(closed);

  final cleaned = cleanupRegions(
    labeled,
    minArea: options.minRegionArea,
    searchRadius: options.neighborSearchRadius,
  );

  return PipelineResult(
    ink: closed,
    regions: cleaned,
    quality: evaluateQuality(cleaned, thresholds: options.thresholds),
  );
}
