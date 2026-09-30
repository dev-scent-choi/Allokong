import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/brush_state.dart';

Stroke _line(List<Offset> pts, {BrushKind kind = BrushKind.crayon}) => Stroke(
      kind: kind,
      color: const Color(0xFFEF7586),
      width: 24,
      points: pts,
    );

void main() {
  test('획 위의 점은 덮여 있다', () {
    final s = _line(const [Offset(0, 0), Offset(100, 0)]);
    expect(s.covers(const Offset(50, 0)), isTrue);
    expect(s.covers(const Offset(50, 11)), isTrue, reason: '굵기 24 의 절반 안');
  });

  test('획에서 굵기 절반보다 먼 점은 덮여 있지 않다', () {
    final s = _line(const [Offset(0, 0), Offset(100, 0)]);
    expect(s.covers(const Offset(50, 13)), isFalse);
    expect(s.covers(const Offset(200, 0)), isFalse, reason: '선분 밖으로 연장되지 않는다');
  });

  test('점이 하나인 획은 원으로 친다', () {
    final s = _line(const [Offset(10, 10)]);
    expect(s.covers(const Offset(10, 21)), isTrue);
    expect(s.covers(const Offset(10, 23)), isFalse);
  });

  test('꺾인 획은 각 선분에서 판정한다', () {
    final s = _line(const [Offset(0, 0), Offset(100, 0), Offset(100, 100)]);
    expect(s.covers(const Offset(100, 50)), isTrue, reason: '두 번째 선분 위');
    expect(s.covers(const Offset(50, 50)), isFalse, reason: '두 선분 사이의 빈 곳');
  });

  test('지우개 획은 잉크로 치지 않는다', () {
    final b = BrushState()
      ..strokes.add(_line(const [Offset(0, 0), Offset(100, 0)],
          kind: BrushKind.eraser));
    expect(b.hasInkAt(const Offset(50, 0)), isFalse,
        reason: '지우개는 잉크를 없앤 자국이지 잉크가 아니다');
  });

  test('크레용 획은 잉크로 친다', () {
    final b = BrushState()
      ..strokes.add(_line(const [Offset(0, 0), Offset(100, 0)]));
    expect(b.hasInkAt(const Offset(50, 0)), isTrue);
    expect(b.hasInkAt(const Offset(50, 90)), isFalse);
  });

  test('빈 상태를 알아본다', () {
    final b = BrushState();
    expect(b.isEmpty, isTrue);
    b.strokes.add(_line(const [Offset(0, 0)]));
    expect(b.isEmpty, isFalse);
  });

  test('획이 늘거나 줄면 개정 번호가 바뀐다', () {
    // 자동 저장이 "브러시가 바뀌었는가"를 이걸로 판단한다. 바뀌지 않았으면
    // 1024 PNG 를 굽지 않는다 (53ms).
    final b = BrushState();
    final r0 = b.revision;
    b.push(_line(const [Offset(0, 0), Offset(10, 10)]));
    expect(b.revision, isNot(r0));
    final r1 = b.revision;
    b.removeStroke(b.strokes.last);
    expect(b.revision, isNot(r1));
  });

  test('clear 는 획과 바탕을 모두 비운다', () {
    final b = BrushState()..strokes.add(_line(const [Offset(0, 0)]));
    b.clear();
    expect(b.isEmpty, isTrue);
    expect(b.strokes, isEmpty);
  });

  test('같은 점이 연달아 있으면 점 하나처럼 동작한다', () {
    // 길이 0 선분만 남는 획이다(점이 둘이라 points.length == 1 지름길을 타지
    // 않는다). 이것은 동작을 고정하는 테스트이지 len2 == 0 가드를 지키는
    // 테스트가 아니다 — 그 가드는 Dart 의 clamp/NaN 동작 때문에 있으나 없으나
    // 결과가 같아서 테스트로 구분할 수 없다. 구현 파일의 주석 참조.
    final only = _line(const [Offset(10, 10), Offset(10, 10)]);
    expect(only.covers(const Offset(10, 10)), isTrue);
    expect(only.covers(const Offset(10, 20)), isTrue, reason: '굵기 24 의 절반 안');
    expect(only.covers(const Offset(10, 30)), isFalse);

    // 길이 0 선분이 정상 선분과 섞여 있어도 정상 선분이 가려지지 않는다.
    final mixed =
        _line(const [Offset(10, 10), Offset(10, 10), Offset(50, 10)]);
    expect(mixed.covers(const Offset(30, 10)), isTrue);
    expect(mixed.covers(const Offset(30, 40)), isFalse);
  });

  test('withPoint 는 원본을 건드리지 않고 새 획을 만든다', () {
    const original = Stroke(
      kind: BrushKind.crayon,
      color: Color(0xFFEF7586),
      width: 24,
      points: [Offset(0, 0)],
    );

    final grown = original.withPoint(const Offset(10, 0));

    expect(original.points, hasLength(1), reason: 'const 획이 그대로여야 한다');
    expect(grown.points, hasLength(2));
    expect(grown.points.last, const Offset(10, 0));
    expect(grown.kind, original.kind);
    expect(grown.width, original.width);
  });
}
