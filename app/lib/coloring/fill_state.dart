import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/painting.dart' show Color;

/// 어느 영역이 무슨 색인지, 그리고 그것을 셰이더가 읽을 팔레트 텍스처로
/// 옮기는 일까지 맡는다.
///
/// 팔레트는 256×256 RGBA 다. 영역 ID `n` 은 좌표 `(n % 256, n ~/ 256)` 에
/// 놓이므로, 셰이더는 ID 의 하위·상위 바이트를 그대로 좌표로 쓸 수 있다.
/// 알파 0 은 "아직 칠하지 않음" 을 뜻한다.
class FillState {
  static const _side = 256;

  final Map<int, Color> _fills = {};
  final Uint8List _lut = Uint8List(_side * _side * 4);

  /// 팔레트 텍스처의 원본 바이트. 테스트와 디버깅용이다.
  Uint8List get lutBytes => _lut;

  /// 채움이 바뀔 때마다 올라간다. 팔레트 텍스처는 이 값에만 의존하므로,
  /// 다시 구울지 말지를 이 값의 변화로만 판단할 수 있다 — 획을 긋는 동안은
  /// 채움이 전혀 바뀌지 않으므로 매 점마다 다시 구울 필요가 없다.
  int _revision = 0;
  int get revision => _revision;

  int get filledCount => _fills.length;

  Color? fillOf(int regionId) => _fills[regionId];

  /// 영역 하나의 색을 정한다. [color] 가 null 이면 미채색으로 되돌린다.
  void setFill(int regionId, Color? color) {
    if (regionId < kRegionFirstFillable) {
      throw ArgumentError(
          '선(0)과 배경(1)은 칠할 수 없습니다: $regionId');
    }
    if (regionId > kMaxRegionId) {
      throw ArgumentError('영역 ID 범위를 벗어났습니다: $regionId');
    }

    final o = ((regionId >> 8) * _side + (regionId & 0xFF)) * 4;
    if (color == null) {
      _fills.remove(regionId);
      _lut[o] = 0;
      _lut[o + 1] = 0;
      _lut[o + 2] = 0;
      _lut[o + 3] = 0;
      _revision++;
      return;
    }

    _fills[regionId] = color;
    _lut[o] = (color.r * 255).round();
    _lut[o + 1] = (color.g * 255).round();
    _lut[o + 2] = (color.b * 255).round();
    _lut[o + 3] = (color.a * 255).round();
    _revision++;
  }

  void clear() {
    _fills.clear();
    _lut.fillRange(0, _lut.length, 0);
    _revision++;
  }

  /// 영역 ID → ARGB 정수. 작품 파일에 그대로 넣는다.
  Map<int, int> toJson() =>
      {for (final e in _fills.entries) e.key: e.value.toARGB32()};

  void loadJson(Map<int, int> json) {
    clear();
    json.forEach((id, argb) => setFill(id, Color(argb)));
  }

  /// 셰이더에 넘길 팔레트 텍스처.
  ///
  /// 256×256 한 장을 만드는 데 0.2ms 정도다. 탭마다 새로 만들어도 한 프레임
  /// 안에 충분히 들어간다.
  Future<ui.Image> paletteImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _lut,
      _side,
      _side,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
