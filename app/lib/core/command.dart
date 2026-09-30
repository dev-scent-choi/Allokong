import 'dart:collection';

import 'package:flutter/painting.dart' show Color;

import '../coloring/brush_state.dart';
import '../coloring/sticker_state.dart';
import 'artwork_state.dart';

/// 되돌릴 수 있는 한 번의 조작.
abstract class Command {
  void apply(ArtworkState state);
  void revert(ArtworkState state);
}

/// 영역 하나의 색을 바꾼 일. `after == null` 이 "칠 지우기"다.
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
  void apply(ArtworkState state) => state.fills.setFill(regionId, after);

  @override
  void revert(ArtworkState state) => state.fills.setFill(regionId, before);
}

/// 획 하나를 그은 일.
///
/// 획에는 바꿔칠 정체성이 없으므로 이전/이후가 아니라 획 자체를 들고 있다.
/// 지우개 획도 이것으로 쌓인다 — 지우개는 잉크를 없애는 획이지 획의 삭제가 아니다.
class StrokeCommand implements Command {
  final Stroke stroke;

  const StrokeCommand(this.stroke);

  @override
  void apply(ArtworkState state) => state.brush.push(stroke);

  @override
  void revert(ArtworkState state) => state.brush.removeStroke(stroke);
}

/// 스티커 하나를 붙이거나 떼거나 옮긴 일.
///
/// [index] 는 z 순서다. 떼었다가 되돌릴 때 원래 자리로 돌아가야 한다.
class StickerCommand implements Command {
  final int index;
  final Sticker? before;
  final Sticker? after;

  const StickerCommand({
    required this.index,
    required this.before,
    required this.after,
  });

  @override
  void apply(ArtworkState state) => _set(state, before, after);

  @override
  void revert(ArtworkState state) => _set(state, after, before);

  void _set(ArtworkState state, Sticker? from, Sticker? to) {
    if (from == null && to != null) {
      state.stickers.insertAt(index, to);
    } else if (from != null && to == null) {
      state.stickers.removeAt(index);
    } else if (from != null && to != null) {
      state.stickers.replaceAt(index, to);
    }
  }
}

/// 한 번의 손짓이 만든 명령 여러 개를 하나로 묶는다.
///
/// 지우개가 "손가락 밑의 맨 위 것"을 지우므로, 한 번 쓸어내리는 동안 브러시
/// 자국을 지우는 획 하나와 벗겨진 채움 여러 개가 함께 나온다. 아이는 되돌리기
/// 한 번에 그 손짓 전체가 돌아오기를 기대한다.
class BatchCommand implements Command {
  final List<Command> commands;

  const BatchCommand(this.commands);

  @override
  void apply(ArtworkState state) {
    for (final c in commands) {
      c.apply(state);
    }
  }

  @override
  void revert(ArtworkState state) {
    // 역순이어야 한다. 같은 대상을 두 번 건드린 묶음은 거꾸로 풀지 않으면
    // 중간 상태가 남는다.
    for (final c in commands.reversed) {
      c.revert(state);
    }
  }
}

/// 되돌리기 스택.
///
/// 다시 실행(redo)은 두지 않는다. 이 연령대에서 되돌리기는 "실수를 쉽게 지우는"
/// 장치이지 편집 히스토리가 아니고, redo 버튼이 하나 더 늘면 도구바가 그만큼
/// 복잡해진다.
class UndoStack {
  final int depth;
  final Queue<Command> _stack = Queue<Command>();

  UndoStack({this.depth = 50});

  bool get canUndo => _stack.isNotEmpty;

  int get length => _stack.length;

  void push(Command command, ArtworkState state) {
    command.apply(state);
    _stack.addLast(command);
    while (_stack.length > depth) {
      _stack.removeFirst();
    }
  }

  bool undo(ArtworkState state) {
    if (_stack.isEmpty) return false;
    _stack.removeLast().revert(state);
    return true;
  }

  void clear() => _stack.clear();
}
