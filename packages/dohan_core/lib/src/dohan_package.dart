import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'index_map.dart';
import 'types.dart';

/// 도안 패키지의 메타데이터. `meta.json`으로 직렬화된다.
class DohanMeta {
  final String id;
  final String title;

  /// `animal` · `car` · `dinosaur` · `character` 중 하나.
  final String category;

  /// `bundled`(앱 내장) 또는 `user`(사용자가 사진에서 변환).
  final String source;

  final List<int> canvasSize;
  final int regionCount;
  final int difficulty;
  final List<String> suggestedPalette;

  /// 영역 ID → [x, y] 중심 좌표. 미완성 영역 힌트 표시에 쓴다.
  final Map<int, List<int>> regionCentroids;

  final DateTime createdAt;

  const DohanMeta({
    required this.id,
    required this.title,
    required this.category,
    required this.source,
    required this.canvasSize,
    required this.regionCount,
    required this.difficulty,
    required this.suggestedPalette,
    required this.regionCentroids,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'source': source,
        'canvasSize': canvasSize,
        'regionCount': regionCount,
        'difficulty': difficulty,
        'suggestedPalette': suggestedPalette,
        'regionCentroids': {
          for (final e in regionCentroids.entries) e.key.toString(): e.value
        },
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory DohanMeta.fromJson(Map<String, dynamic> json) => DohanMeta(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String,
        source: json['source'] as String,
        canvasSize: (json['canvasSize'] as List).cast<int>(),
        regionCount: json['regionCount'] as int,
        difficulty: json['difficulty'] as int,
        suggestedPalette: (json['suggestedPalette'] as List).cast<String>(),
        regionCentroids: {
          for (final e in (json['regionCentroids'] as Map).entries)
            int.parse(e.key as String): (e.value as List).cast<int>()
        },
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// 디스크에서 읽어 들인 도안 한 벌.
class DohanPackage {
  final DohanMeta meta;
  final img.Image lineart;
  final RegionMap regions;

  const DohanPackage({
    required this.meta,
    required this.lineart,
    required this.regions,
  });
}

/// 칠할 수 있는 영역별 픽셀 중심 좌표를 구한다.
Map<int, List<int>> computeRegionCentroids(RegionMap map) {
  final sumX = <int, int>{};
  final sumY = <int, int>{};
  final count = <int, int>{};
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final id = map.at(x, y);
      if (id < kRegionFirstFillable) continue;
      sumX[id] = (sumX[id] ?? 0) + x;
      sumY[id] = (sumY[id] ?? 0) + y;
      count[id] = (count[id] ?? 0) + 1;
    }
  }
  return {
    for (final id in count.keys)
      id: [sumX[id]! ~/ count[id]!, sumY[id]! ~/ count[id]!]
  };
}

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
  final DohanMeta meta;
  try {
    meta = DohanMeta.fromJson(jsonDecode(metaText) as Map<String, dynamic>);
  } catch (e) {
    throw FormatException('meta.json의 내용을 해석할 수 없습니다 (${dir.path}): $e');
  }

  final lineartBytes = await _readBytes(dir, 'lineart.png');
  final lineart = img.decodePng(lineartBytes);
  if (lineart == null) {
    throw FormatException('lineart.png를 디코딩할 수 없습니다 (${dir.path}).');
  }

  final regionBytes = await _readBytes(dir, 'regions.png');

  return DohanPackage(
    meta: meta,
    lineart: lineart,
    regions: decodeIndexMapPng(regionBytes),
  );
}
