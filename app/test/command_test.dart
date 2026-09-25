import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/fill_state.dart';
import 'package:kkumul/core/command.dart';

void main() {
  const red = Color(0xFFFF0000);
  const blue = Color(0xFF0000FF);

  test('칠하기를 되돌리면 이전 색으로 돌아간다', () {
    final fills = FillState();
    final stack = UndoStack();

    stack.push(
        const FillCommand(regionId: 2, before: null, after: red), fills);
    expect(fills.fillOf(2), red);

    expect(stack.undo(fills), isTrue);
    expect(fills.fillOf(2), isNull);
  });

  test('덧칠을 되돌리면 그 전 색으로 돌아간다', () {
    final fills = FillState();
    final stack = UndoStack();

    stack.push(const FillCommand(regionId: 2, before: null, after: red), fills);
    stack.push(const FillCommand(regionId: 2, before: red, after: blue), fills);
    expect(fills.fillOf(2), blue);

    stack.undo(fills);
    expect(fills.fillOf(2), red, reason: '한 단계만 되돌린다');

    stack.undo(fills);
    expect(fills.fillOf(2), isNull);
  });

  test('되돌릴 것이 없으면 false 를 돌려준다', () {
    expect(UndoStack().undo(FillState()), isFalse);
    expect(UndoStack().canUndo, isFalse);
  });

  test('여러 영역을 섞어 칠해도 순서대로 되돌아간다', () {
    final fills = FillState();
    final stack = UndoStack();

    stack.push(const FillCommand(regionId: 2, before: null, after: red), fills);
    stack.push(const FillCommand(regionId: 3, before: null, after: blue), fills);
    stack.push(const FillCommand(regionId: 2, before: red, after: blue), fills);

    stack.undo(fills);
    expect(fills.fillOf(2), red);
    expect(fills.fillOf(3), blue);

    stack.undo(fills);
    expect(fills.fillOf(3), isNull);

    stack.undo(fills);
    expect(fills.fillOf(2), isNull);
    expect(stack.canUndo, isFalse);
  });

  test('스택 깊이를 넘으면 가장 오래된 것부터 버린다', () {
    final fills = FillState();
    final stack = UndoStack(depth: 3);

    for (var i = 0; i < 5; i++) {
      stack.push(
          FillCommand(regionId: 2 + i, before: null, after: red), fills);
    }

    expect(stack.length, 3);
    while (stack.canUndo) {
      stack.undo(fills);
    }
    // 버려진 두 개는 되돌릴 수 없으므로 칠해진 채로 남는다.
    expect(fills.fillOf(2), red);
    expect(fills.fillOf(3), red);
    expect(fills.fillOf(4), isNull);
  });
}
