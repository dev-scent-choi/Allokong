import 'dart:typed_data';
import 'dart:ui' as ui;

import '../coloring/coloring_painter.dart';

/// 갤러리 썸네일 한 변의 픽셀 수.
///
/// 2열 격자의 한 칸이 약 144dp 다. 256 이면 고해상도 화면에서도 충분하고,
/// 1024² 를 그대로 쓰는 것보다 픽셀 수가 16 배 적다.
const int kThumbnailSize = 256;

/// 썸네일을 굽는 함수. 화면이 텍스처를 다 올린 뒤 컨트롤러에 꽂는다.
///
/// 텍스처가 아직 없으면 `null` 을 돌려준다 — 그때는 쓰지 않는다.
typedef ThumbnailBaker = Future<Uint8List?> Function();

/// 합성된 도안을 [kThumbnailSize] 정사각 PNG 로 굽는다.
///
/// [painter] 는 도안의 논리 좌표계([canvasSize] × [canvasSize])로 그린다.
/// 여기서 축소 변환을 한 번 걸면 흰 배경·채움·브러시·선화·스티커가 모두
/// 그대로 줄어든다 — 화면에 보이던 것과 같은 그림이다.
Future<Uint8List?> bakeThumbnail(
  ColoringPainter painter,
  int canvasSize,
) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.scale(kThumbnailSize / canvasSize);
  painter.paint(canvas, ui.Size(canvasSize.toDouble(), canvasSize.toDouble()));
  final picture = rec.endRecording();
  final image = await picture.toImage(kThumbnailSize, kThumbnailSize);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return null;
  // ByteData 는 더 큰 버퍼의 조각일 수 있다. .buffer 를 그대로 쓰면
  // offsetInBytes 를 무시해 엉뚱한 자리에서 읽는다.
  return Uint8List.sublistView(data);
}
