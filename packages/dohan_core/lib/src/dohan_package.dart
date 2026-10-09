import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'index_map.dart';
import 'types.dart';

/// 도안 패키지의 메타데이터. `meta.json`으로 직렬화된다.
class DohanMeta {
  final String id;
  final String title;

  /// `animal` · `car` · `dinosaur` · `shape` 중 하나.
  final String category;

  /// `bundled`(앱 내장) 또는 `user`(사용자가 사진에서 변환).
  final String source;

  final List<int> canvasSize;
  final int regionCount;
  final int difficulty;
  final List<String> suggestedPalette;

  /// 영역 ID → [x, y]. 각 영역 안에서 내접원이 가장 큰 지점이다. 미완성 영역 힌트 표시에 쓴다.
  final Map<int, List<int>> regionAnchors;

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
    required this.regionAnchors,
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
        'regionAnchors': {
          for (final e in regionAnchors.entries) e.key.toString(): e.value
        },
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  /// JSON 문자열을 해석한다. 실패하면 출처를 지목하는 한국어 예외를 던진다.
  ///
  /// [label] 은 어느 도안이 깨졌는지 사람이 알아볼 이름이다 — 디렉터리 경로든
  /// 에셋 키든 상관없다.
  static DohanMeta parse(String json, {String label = '(바이트)'}) {
    try {
      return DohanMeta.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      throw FormatException('meta.json의 내용을 해석할 수 없습니다 ($label): $e');
    }
  }

  factory DohanMeta.fromJson(Map<String, dynamic> json) => DohanMeta(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String,
        source: json['source'] as String,
        canvasSize: (json['canvasSize'] as List).cast<int>(),
        regionCount: json['regionCount'] as int,
        difficulty: json['difficulty'] as int,
        suggestedPalette: (json['suggestedPalette'] as List).cast<String>(),
        regionAnchors: {
          for (final e in (json['regionAnchors'] as Map).entries)
            int.parse(e.key as String): (e.value as List).cast<int>()
        },
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// 도안 한 벌. 메타데이터와 선화, 영역 맵을 함께 들고 있다.
class DohanPackage {
  final DohanMeta meta;
  final img.Image lineart;
  final RegionMap regions;

  const DohanPackage({
    required this.meta,
    required this.lineart,
    required this.regions,
  });

  /// 바이트 세 벌에서 도안을 만든다.
  ///
  /// 앱에 내장된 도안은 Flutter 에셋이라 `File` 이 아니고 경로로 읽을 수 없다.
  /// 에셋 번들에서 받은 바이트를 그대로 넘기면 된다. 디스크에서 읽는 경로는
  /// `dohan_core_io.dart` 의 `readDohanPackage` 가 이 생성자를 쓴다.
  ///
  /// [label] 은 실패 메시지에 붙는 출처 표시다 — 디렉터리 경로든 에셋 키든,
  /// 어느 도안이 깨졌는지 사람이 알아볼 수 있는 이름을 넘긴다.
  factory DohanPackage.fromBytes({
    required String metaJson,
    required Uint8List lineartPng,
    required Uint8List regionsPng,
    String label = '(바이트)',
  }) {
    final meta = DohanMeta.parse(metaJson, label: label);

    final lineart = img.decodePng(lineartPng);
    if (lineart == null) {
      throw FormatException('lineart.png를 디코딩할 수 없습니다 ($label).');
    }

    return DohanPackage(
      meta: meta,
      lineart: lineart,
      regions: decodeIndexMapPng(regionsPng),
    );
  }
}
