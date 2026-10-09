import 'dart:convert';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/services.dart';

import '../core/dohan_source.dart';

/// 앱 번들에 실린 도안을 읽는다.
///
/// 에셋은 `File` 이 아니므로 `readDohanPackage` 를 쓸 수 없다. 바이트를 받아
/// `DohanPackage.fromBytes` 로 조립한다.
class BundledDohanSource implements DohanSource {
  /// 번들에 실린 도안 ID. pubspec 의 `assets` 목록과 짝이 맞아야 한다.
  ///
  /// 순서가 `놀기` 의 카테고리별 격자 순서가 된다.
  static const defaultIds = [
    'animal-cat-01',
    'animal-fish-01',
    'animal-bird-01',
    'car-sedan-01',
    'car-truck-01',
    'car-bus-01',
    'dino-stego-01',
    'dino-trex-01',
    'dino-bronto-01',
    'flower-01',
    'shape-star-01',
    'shape-house-01',
  ];

  final AssetBundle _bundle;
  final List<String> _ids;

  BundledDohanSource({AssetBundle? bundle, List<String>? ids})
      : _bundle = bundle ?? rootBundle,
        _ids = ids ?? defaultIds;

  @override
  Future<List<String>> listIds() async => List.unmodifiable(_ids);

  @override
  Future<DohanPackage> load(String id) async {
    if (!_ids.contains(id)) {
      throw ArgumentError('내장 도안에 없는 ID 입니다: $id');
    }
    final dir = 'assets/dohans/$id';
    final meta = await _bundle.load('$dir/meta.json');
    final lineart = await _bundle.load('$dir/lineart.png');
    final regions = await _bundle.load('$dir/regions.png');

    return DohanPackage.fromBytes(
      // ByteData 는 더 큰 버퍼의 조각일 수 있다. .buffer 를 그대로 쓰면
      // offsetInBytes 를 무시해 엉뚱한 자리에서 읽는다 — Flutter 문서와
      // asset_bundle.dart 내부가 모두 sublistView 를 쓰는 이유다.
      metaJson: utf8.decode(Uint8List.sublistView(meta)),
      lineartPng: Uint8List.sublistView(lineart),
      regionsPng: Uint8List.sublistView(regions),
      label: dir,
    );
  }
}
