import 'dart:collection';

import 'package:flutter/painting.dart' show Color;

import '../coloring/fill_state.dart';

/// 되돌릴 수 있는 한 번의 조작.
abstract class Command {
  void apply(FillState fills);
  void revert(FillState fills);
}

/// 영역 하나의 색을 바꾼 일.
///
/// 이전 색과 새 색만 들고 있으면 되므로 수십 바이트다. 레이어를 통째로
/// 스냅샷하는 것과 비교가 되지 않는다.
class FillCommand implements Command {
  final int regionId;
  final Color? before;
  final Color? after;

  const FillCommand({
    required this.regionId,
    required this.before,
    required this.after,
  });

  @override
  void apply(FillState fills) => fills.setFill(regionId, after);

  @override
  void revert(FillState fills) => fills.setFill(regionId, before);
}

/// 되돌리기 스택.
///
/// 다시 실행(redo)은 두지 않는다. 기획서의 연령대에서 되돌리기는 "실수를 쉽게
/// 지우는" 장치이지 편집 히스토리가 아니고, redo 버튼이 하나 더 늘면 도구바가
/// 그만큼 복잡해진다.
class UndoStack {
  final int depth;
  final Queue<Command> _stack = Queue<Command>();

  UndoStack({this.depth = 50});

  bool get canUndo => _stack.isNotEmpty;

  int get length => _stack.length;

  /// 명령을 적용하고 스택에 쌓는다.
  void push(Command command, FillState fills) {
    command.apply(fills);
    _stack.addLast(command);
    while (_stack.length > depth) {
      _stack.removeFirst();
    }
  }

  /// 마지막 명령을 되돌린다. 되돌릴 것이 없으면 false.
  bool undo(FillState fills) {
    if (_stack.isEmpty) return false;
    _stack.removeLast().revert(fills);
    return true;
  }

  void clear() => _stack.clear();
}
