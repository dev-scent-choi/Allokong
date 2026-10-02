
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/brush_state.dart';
import 'package:kkumul/coloring/sticker_state.dart';
import 'package:kkumul/core/artwork_state.dart';
import 'package:kkumul/core/command.dart';

const _pink = Color(0xFFEF7586);
const _blue = Color(0xFF6CAEE0);

Stroke _stroke() => const Stroke(
      kind: BrushKind.crayon,
      color: _pink,
      width: 24,
      points: [Offset(0, 0), Offset(10, 10)],
    );

Sticker _sticker(String id) =>
    Sticker(instanceId: id, stickerId: 'star-01', x: 100, y: 100);

void main() {
  test('채움 명령이 색을 바꾸고 되돌린다', () {
    final state = ArtworkState();
    UndoStack().push(
      const FillCommand(regionId: 2, before: null, after: _pink),
      state,
    );
    expect(state.fills.fillOf(2), _pink);
  });

  test('되돌리면 이전 색으로 간다', () {
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(const FillCommand(regionId: 2, before: null, after: _pink), state);
    stack.push(const FillCommand(regionId: 2, before: _pink, after: _blue), state);

    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(2), _pink);
    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(2), isNull);
    expect(stack.undo(state), isFalse);
  });

  test('스택 깊이를 넘으면 오래된 것부터 버린다', () {
    final state = ArtworkState();
    final stack = UndoStack(depth: 3);
    for (var i = 0; i < 5; i++) {
      stack.push(
        FillCommand(regionId: 2 + i, before: null, after: _pink),
        state,
      );
    }
    expect(stack.length, 3);

    // 어느 쪽을 버렸는지까지 봐야 한다. 개수만 보면 가장 최근 것을 버리는
    // 구현도 통과한다 — 아이가 방금 한 일을 되돌릴 수 없게 되는데도.
    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(6), isNull, reason: '가장 최근 것부터 되돌아간다');
    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(5), isNull);
    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(4), isNull);
    expect(stack.undo(state), isFalse, reason: '2·3 번은 이미 버려졌다');
    expect(state.fills.fillOf(2), _pink, reason: '버려진 것은 되돌아오지 않는다');
  });

  test('되돌릴 것이 없으면 false 다', () {
    expect(UndoStack().undo(ArtworkState()), isFalse);
  });

  test('clear 하면 되돌릴 것이 없어진다', () {
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(const FillCommand(regionId: 2, before: null, after: _pink), state);
    stack.clear();
    expect(stack.canUndo, isFalse);
  });

  test('획 명령이 획을 넣고 뺀다', () {
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(StrokeCommand(_stroke()), state);
    expect(state.brush.strokes, hasLength(1));

    expect(stack.undo(state), isTrue);
    expect(state.brush.strokes, isEmpty);
  });

  test('스티커 명령이 추가·삭제·이동을 되돌린다', () {
    final state = ArtworkState();
    final stack = UndoStack();

    stack.push(
      StickerCommand(index: 0, before: null, after: _sticker('a')),
      state,
    );
    expect(state.stickers.stickers, hasLength(1));

    final moved = state.stickers.stickers.first.copyWith(x: 500);
    stack.push(
      StickerCommand(
          index: 0, before: state.stickers.stickers.first, after: moved),
      state,
    );
    expect(state.stickers.stickers.first.x, 500);

    expect(stack.undo(state), isTrue);
    expect(state.stickers.stickers.first.x, 100, reason: '이동 되돌리기');
    expect(stack.undo(state), isTrue);
    expect(state.stickers.stickers, isEmpty, reason: '추가 되돌리기');
  });

  test('스티커를 지웠다 되돌리면 원래 자리로 돌아온다', () {
    final state = ArtworkState();
    state.stickers
      ..insertAt(0, _sticker('a'))
      ..insertAt(1, _sticker('b'))
      ..insertAt(2, _sticker('c'));

    final stack = UndoStack();
    stack.push(
      StickerCommand(index: 1, before: _sticker('b'), after: null),
      state,
    );
    expect(state.stickers.stickers.map((s) => s.instanceId), ['a', 'c']);

    expect(stack.undo(state), isTrue);
    expect(state.stickers.stickers.map((s) => s.instanceId), ['a', 'b', 'c'],
        reason: 'z 순서까지 복원해야 한다');
  });

  test('묶음 명령은 한 번에 되돌아간다', () {
    // 지우개 한 손짓이 스티커 하나와 채움 셋을 건드려도 되돌리기는 한 번이다.
    final state = ArtworkState();
    state.fills
      ..setFill(2, _pink)
      ..setFill(3, _pink)
      ..setFill(4, _pink);
    state.stickers.insertAt(0, _sticker('a'));

    final stack = UndoStack();
    stack.push(
      BatchCommand([
        StickerCommand(index: 0, before: _sticker('a'), after: null),
        const FillCommand(regionId: 2, before: _pink, after: null),
        const FillCommand(regionId: 3, before: _pink, after: null),
        const FillCommand(regionId: 4, before: _pink, after: null),
      ]),
      state,
    );

    expect(state.stickers.stickers, isEmpty);
    expect(state.fills.filledCount, 0);

    expect(stack.undo(state), isTrue);

    expect(state.stickers.stickers, hasLength(1));
    expect(state.fills.filledCount, 3, reason: '되돌리기 한 번에 넷이 다 돌아온다');
    expect(stack.canUndo, isFalse);
  });

  test('묶음은 역순으로 되돌린다', () {
    // 같은 영역을 두 번 건드린 묶음은 순서를 거꾸로 풀어야 원래대로 돌아온다.
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(
      const BatchCommand([
        FillCommand(regionId: 2, before: null, after: _pink),
        FillCommand(regionId: 2, before: _pink, after: _blue),
      ]),
      state,
    );
    expect(state.fills.fillOf(2), _blue);

    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(2), isNull,
        reason: '역순이 아니면 분홍이 남는다');
  });

  test('조작 순서 그대로 거꾸로 되돌아간다', () {
    // 레이어별로 스택을 쪼개면 깨지는 성질이다.
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(const FillCommand(regionId: 2, before: null, after: _pink), state);
    stack.push(StrokeCommand(_stroke()), state);
    stack.push(
      StickerCommand(index: 0, before: null, after: _sticker('a')),
      state,
    );

    stack.undo(state);
    expect(state.stickers.stickers, isEmpty, reason: '스티커가 먼저');
    stack.undo(state);
    expect(state.brush.strokes, isEmpty, reason: '그다음 획');
    stack.undo(state);
    expect(state.fills.filledCount, 0, reason: '마지막이 채움');
  });
}
