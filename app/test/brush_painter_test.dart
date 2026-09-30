import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/brush_painter.dart';
import 'package:kkumul/coloring/brush_state.dart';
import 'package:kkumul/coloring/paintable_mask.dart';

const _red = Color(0xFFFF0000);

Stroke _across(int w, {BrushKind kind = BrushKind.brush}) => Stroke(
      kind: kind,
      color: _red,
      width: 8,
      points: [const ui.Offset(0, 0.5), ui.Offset(w.toDouble(), 0.5)],
    );

/// [w] x 1 캔버스에 브러시 레이어만 그려 픽셀을 읽는다.
Future<List<List<int>>> _render(int w, BrushState brush, ui.Image? mask) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  BrushPainter.paint(
      canvas, ui.Rect.fromLTWH(0, 0, w.toDouble(), 1), brush, mask);
  final img = await rec.endRecording().toImage(w, 1);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return [
    for (var x = 0; x < w; x++)
      [
        bytes.getUint8(x * 4),
        bytes.getUint8(x * 4 + 1),
        bytes.getUint8(x * 4 + 2),
        bytes.getUint8(x * 4 + 3),
      ],
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('칠할 수 없는 픽셀에는 브러시가 남지 않는다', () async {
    // 왼쪽 4 = 칠할 수 있음, 오른쪽 4 = 선
    final mask = await buildPaintableMask(
      RegionMap(8, 1, Uint16List.fromList([2, 2, 2, 2, 0, 0, 0, 0])),
    );
    final brush = BrushState()..push(_across(8));

    final px = await _render(8, brush, mask);

    for (var x = 0; x < 4; x++) {
      expect(px[x][3], greaterThan(0), reason: '$x 번 픽셀은 칠해져야 한다');
    }
    for (var x = 4; x < 8; x++) {
      expect(px[x], [0, 0, 0, 0], reason: '$x 번 픽셀은 선이라 잘려야 한다');
    }
  });

  test('배경 위에도 남지 않는다', () async {
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([1, 1, 2, 2])),
    );
    final brush = BrushState()..push(_across(4));

    final px = await _render(4, brush, mask);

    expect(px[0], [0, 0, 0, 0]);
    expect(px[1], [0, 0, 0, 0]);
    expect(px[2][3], greaterThan(0));
  });

  test('영역 경계는 넘나든다', () async {
    // 2 와 3 은 다른 영역이지만 둘 다 칠할 수 있으므로 획이 이어져야 한다.
    // 상위 스펙 7.3 이 의도한 관대함이다.
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([2, 2, 3, 3])),
    );
    final brush = BrushState()..push(_across(4));

    final px = await _render(4, brush, mask);

    for (var x = 0; x < 4; x++) {
      expect(px[x][3], greaterThan(0), reason: '$x 번에서 끊기면 안 된다');
    }
  });

  test('지우개 획이 앞선 잉크를 지운다', () async {
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([2, 2, 2, 2])),
    );
    final brush = BrushState()
      ..push(_across(4))
      ..push(const Stroke(
        kind: BrushKind.eraser,
        color: _red,
        width: 8,
        points: [ui.Offset(2.5, 0.5), ui.Offset(4, 0.5)],
      ));

    final px = await _render(4, brush, mask);

    expect(px[0][3], greaterThan(0), reason: '지우지 않은 왼쪽은 남는다');
    expect(px[3], [0, 0, 0, 0], reason: '지운 오른쪽은 비어야 한다');
  });

  test('그리는 중인 획도 보인다', () async {
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([2, 2, 2, 2])),
    );
    final brush = BrushState()..live = _across(4);

    final px = await _render(4, brush, mask);

    expect(px[1][3], greaterThan(0), reason: '손가락을 떼기 전에도 그려져야 한다');
  });

  test('아무것도 없으면 아무것도 그리지 않는다', () async {
    final px = await _render(4, BrushState(), null);
    for (final p in px) {
      expect(p, [0, 0, 0, 0]);
    }
  });

  test('크레용은 붓보다 옅다', () async {
    final mask = await buildPaintableMask(
      RegionMap(2, 1, Uint16List.fromList([2, 2])),
    );
    final crayon = await _render(
        2, BrushState()..push(_across(2, kind: BrushKind.crayon)), mask);
    final brush = await _render(
        2, BrushState()..push(_across(2, kind: BrushKind.brush)), mask);

    expect(crayon[0][3], lessThan(brush[0][3]),
        reason: '겹쳐 그으면 진해지는 크레용 느낌');
  });
}
