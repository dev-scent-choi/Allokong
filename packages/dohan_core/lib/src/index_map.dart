import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'types.dart';

/// 영역 맵을 무손실 PNG로 인코딩한다.
///
/// 색상 이미지가 아니라 데이터다. 리샘플링, 손실 압축, 팔레트 양자화를
/// 거치면 영역 ID가 손상되므로 이 함수가 만든 바이트를 그대로 저장해야 한다.
Uint8List encodeIndexMapPng(RegionMap map) {
  final im = img.Image(width: map.width, height: map.height, numChannels: 4);
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final rgba = encodeRegionId(map.at(x, y));
      im.setPixelRgba(x, y, rgba[0], rgba[1], rgba[2], rgba[3]);
    }
  }
  return img.encodePng(im, level: 9);
}

/// 인덱스맵 PNG에서 영역 맵을 복원한다.
RegionMap decodeIndexMapPng(Uint8List bytes) {
  final im = img.decodePng(bytes);
  if (im == null) {
    throw const FormatException('인덱스맵 PNG를 디코딩할 수 없습니다.');
  }
  final map = RegionMap.filled(im.width, im.height, kRegionLine);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      map.set(x, y, decodeRegionId(p.r.toInt(), p.g.toInt()));
    }
  }
  return map;
}
