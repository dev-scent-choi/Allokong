import 'dart:ui';

import 'package:dohan_core/dohan_core.dart';

/// 화면 좌표와 도안 캔버스 좌표 사이의 변환.
///
/// 도안은 항상 정사각형이고, 화면에 비율을 지켜 가운데 맞춤으로 넣는다.
/// 위젯을 모르는 순수 계산이라 화면 없이 테스트할 수 있다 — 아이가 누른 곳과
/// 칠해지는 곳이 어긋나는 것은 조용히 일어나는 종류의 버그라, 이 계산만
/// 따로 잠가 둔다.
class CanvasTransform {
  /// 그릴 수 있는 화면 영역의 크기.
  final Size viewSize;

  /// 도안 캔버스 한 변의 픽셀 수 (보통 1024).
  final int canvasSize;

  /// 캔버스 1픽셀이 화면 몇 픽셀인지.
  final double scale;

  /// 화면에서 도안이 시작하는 왼쪽 위 지점.
  final Offset offset;

  const CanvasTransform({
    required this.viewSize,
    required this.canvasSize,
    required this.scale,
    required this.offset,
  });

  /// 도안을 화면에 비율을 지켜 가운데 맞춤으로 넣는 변환.
  factory CanvasTransform.fit(Size viewSize, int canvasSize) {
    final shortest =
        viewSize.width < viewSize.height ? viewSize.width : viewSize.height;
    final scale = shortest / canvasSize;
    final drawn = canvasSize * scale;
    return CanvasTransform(
      viewSize: viewSize,
      canvasSize: canvasSize,
      scale: scale,
      offset: Offset(
        (viewSize.width - drawn) / 2,
        (viewSize.height - drawn) / 2,
      ),
    );
  }

  /// 화면 좌표를 캔버스 좌표로.
  Offset toCanvas(Offset viewPoint) => Offset(
        (viewPoint.dx - offset.dx) / scale,
        (viewPoint.dy - offset.dy) / scale,
      );

  /// 캔버스 좌표를 화면 좌표로.
  Offset toView(Offset canvasPoint) => Offset(
        canvasPoint.dx * scale + offset.dx,
        canvasPoint.dy * scale + offset.dy,
      );

  /// 화면에서 도안이 실제로 그려지는 사각형.
  Rect get destRect => Rect.fromLTWH(
        offset.dx,
        offset.dy,
        canvasSize * scale,
        canvasSize * scale,
      );
}

/// 캔버스 좌표가 가리키는 영역 ID.
///
/// 캔버스 밖은 [kRegionBackground] 로 본다 — 여백을 눌러도 아무 일이 없어야
/// 한다. 좌표는 내림해서 픽셀을 고른다. 인덱스맵은 데이터이므로 보간하지
/// 않는다.
int regionAt(RegionMap regions, Offset canvasPoint) {
  final x = canvasPoint.dx.floor();
  final y = canvasPoint.dy.floor();
  if (x < 0 || y < 0 || x >= regions.width || y >= regions.height) {
    return kRegionBackground;
  }
  return regions.at(x, y);
}
