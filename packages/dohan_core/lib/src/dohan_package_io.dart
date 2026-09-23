import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'dohan_package.dart';
import 'index_map.dart';
import 'types.dart';

Future<Uint8List> _readBytes(Directory dir, String name) async {
  try {
    return await File('${dir.path}/$name').readAsBytes();
  } on FileSystemException catch (e) {
    throw FormatException('$name 파일을 열 수 없습니다 (${dir.path}): ${e.message}');
  }
}

Future<String> _readText(Directory dir, String name) async {
  try {
    return await File('${dir.path}/$name').readAsString();
  } on FileSystemException catch (e) {
    throw FormatException('$name 파일을 열 수 없습니다 (${dir.path}): ${e.message}');
  }
}

/// 도안 패키지 세 파일을 [dir]에 쓴다.
Future<void> writeDohanPackage({
  required Directory dir,
  required img.Image lineart,
  required RegionMap regions,
  required DohanMeta meta,
}) async {
  await dir.create(recursive: true);
  await File('${dir.path}/lineart.png')
      .writeAsBytes(img.encodePng(lineart, level: 9));
  await File('${dir.path}/regions.png')
      .writeAsBytes(encodeIndexMapPng(regions));
  await File('${dir.path}/meta.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(meta.toJson()),
  );
}

/// [dir]의 도안 패키지를 읽는다.
///
/// 어느 파일에서 실패했는지 한국어로 알려준다. 앱이 사용자에게 보여줄 안내를
/// 고르려면 파일 단위로 원인을 구분할 수 있어야 한다.
Future<DohanPackage> readDohanPackage(Directory dir) async {
  final metaText = await _readText(dir, 'meta.json');
  // 이미지를 읽기 전에 메타부터 해석한다. 메타가 깨진 패키지는 이미지가
  // 멀쩡해도 못 쓰고, 무엇이 잘못됐는지도 이쪽이 정확하게 알려준다.
  // fromBytes 가 한 번 더 해석하지만 작은 JSON 이라 무시할 만하고,
  // 패키지를 만드는 경로가 하나로 유지된다.
  DohanMeta.parse(metaText, label: dir.path);

  final lineartBytes = await _readBytes(dir, 'lineart.png');
  final regionBytes = await _readBytes(dir, 'regions.png');

  return DohanPackage.fromBytes(
    metaJson: metaText,
    lineartPng: lineartBytes,
    regionsPng: regionBytes,
    label: dir.path,
  );
}
