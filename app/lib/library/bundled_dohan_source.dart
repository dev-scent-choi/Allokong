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
  static const defaultIds = ['flower-01'];

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
      metaJson: utf8.decode(meta.buffer.asUint8List()),
      lineartPng: Uint8List.view(lineart.buffer),
      regionsPng: Uint8List.view(regions.buffer),
      label: dir,
    );
  }
}
