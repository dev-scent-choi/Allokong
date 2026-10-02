import 'dart:async';
import 'dart:ui' show Offset;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../core/artwork.dart';
import '../core/artwork_state.dart';
import '../core/command.dart';
import '../core/dohan_source.dart';
import '../gallery/autosave.dart';
import '../settings/settings.dart';
import '../ui/palette_shades.dart';
import 'canvas_transform.dart';
import 'fill_state.dart';

/// 도구 다섯 가지. 상위 스펙 9장의 아동 모드 도구 목록이다.
enum ToolKind { bucket, crayon, brush, eraser, sticker }

/// 색칠 화면의 상태를 한곳에 묶는다.
///
/// 위젯을 모른다 — 탭 좌표는 이미 캔버스 좌표로 바뀐 것을 받는다. 화면 없이
/// 테스트할 수 있어야 색칠 규칙을 위젯 테스트의 복잡도 없이 잠글 수 있다.
class ColoringController extends ChangeNotifier {
  final DohanSource source;
  final Autosave autosave;
  AgeMode ageMode;

  ColoringController({
    required this.source,
    required this.autosave,
    this.ageMode = AgeMode.toddler,
  });

  DohanPackage? _dohan;
  String? _artworkId;
  final ArtworkState _state = ArtworkState();
  final UndoStack _undo = UndoStack();
  int _openGeneration = 0;

  ToolKind _tool = ToolKind.bucket;
  Shade _shade = Shade.base;
  int _colorIndex = 0;

  /// 유아 모드의 "연속 한 번" 제한을 세는 값. 새로 무언가를 하면 0 이 된다.
  int _undosSinceChange = 0;

  DohanPackage? get dohan => _dohan;
  FillState get fills => _state.fills;
  ArtworkState get state => _state;
  ToolKind get tool => _tool;
  Shade get shade => _shade;
  int get colorIndex => _colorIndex;

  /// 고른 자리와 명도가 만나는 색.
  Color get selectedColor => paletteShades[_shade]![_colorIndex];

  /// 유아 모드는 연속 한 번만 되돌린다(상위 스펙 9장). 내부 스택은 동일하다.
  bool get canUndo =>
      _undo.canUndo &&
      !(ageMode == AgeMode.toddler && _undosSinceChange >= 1);
  bool get isReady => _dohan != null;

  /// 도안을 열고, 이어 그리던 작품이 있으면 그 상태를 얹는다.
  Future<void> open({
    required String dohanId,
    required String artworkId,
    Artwork? existing,
  }) async {
    final generation = ++_openGeneration;

    // 갈아타기 전에 이전 작품의 예약된 저장을 끝낸다. Autosave 의 _pending 은
    // 한 칸뿐이라, 그냥 두면 다음 schedule() 이 그것을 덮어쓰면서 타이머까지
    // 취소한다 — 아이가 마지막으로 칠한 것이 아무 소리 없이 사라진다.
    await autosave.flush();

    final dohan = await source.load(dohanId);

    // 빠르게 두 번 열면 먼저 시작한 쪽이 나중에 끝날 수 있다. 그 결과를 얹으면
    // 아이가 마지막에 고른 도안이 아닌 것이 화면에 뜬다.
    if (generation != _openGeneration) return;

    _dohan = dohan;
    _artworkId = artworkId;
    _undo.clear();
    _state.clear();
    if (existing != null) _state.fills.loadJson(existing.fills);
    notifyListeners();
  }

  void selectTool(ToolKind next) {
    if (_tool == next) return;
    _tool = next;
    notifyListeners();
  }

  /// 앱바의 명도 버튼. 밝게 → 기본 → 어둡게 → 밝게.
  ///
  /// 고른 **자리**는 그대로 두고 색만 갈아끼운다. 아이가 고른 것은 "네 번째
  /// 크레용"이지 특정 hex 가 아니다.
  void cycleShade() {
    _shade = _shade.next;
    notifyListeners();
  }

  void pickColorIndex(int index) {
    if (index < 0 || index >= paletteShades[_shade]!.length) return;
    _colorIndex = index;
    notifyListeners();
  }

  /// 캔버스 좌표를 칠한다. 실제로 바뀐 것이 있으면 true.
  bool tapAt(Offset canvasPoint) {
    // 양동이일 때만 탭으로 칠한다. 크레용·붓·지우개는 끌어서 쓰는 도구고,
    // 스티커는 서랍에서 고른다.
    if (_tool != ToolKind.bucket) return false;

    final dohan = _dohan;
    if (dohan == null) return false;

    final id = regionAt(dohan.regions, canvasPoint);
    if (id < kRegionFirstFillable) return false;

    final before = _state.fills.fillOf(id);
    if (before == selectedColor) return false;

    _undo.push(
      // const 를 붙이면 안 된다 — id·before·selectedColor 가 전부 런타임 값이라
      // "Arguments of a constant creation must be constant expressions" 로
      // 컴파일이 깨진다. FillCommand 의 생성자가 const 인 것과는 별개다.
      FillCommand(regionId: id, before: before, after: selectedColor),
      _state,
    );
    _afterChange();
    return true;
  }

  bool undo() {
    if (!canUndo) return false;
    if (!_undo.undo(_state)) return false;
    _undosSinceChange++;
    _scheduleSave();
    notifyListeners();
    return true;
  }

  /// 조작 하나가 끝났을 때 공통으로 하는 일.
  ///
  /// 되돌리기 예산을 되살리고, 저장을 예약하고, 화면을 다시 그린다. 셋을 따로
  /// 두면 나중에 도구를 추가하는 사람이 하나를 빠뜨린다 — 특히
  /// `_undosSinceChange = 0` 을 빠뜨리면 아이가 새로 그린 뒤에도 되돌리기가
  /// 막혀 있고, 그것을 잡는 테스트는 없다. 브러시·스티커를 붙이는 태스크도
  /// 반드시 이것을 부른다.
  void _afterChange() {
    _undosSinceChange = 0;
    _scheduleSave();
    notifyListeners();
  }

  /// 화면을 떠나기 전에 예약된 저장을 마무리한다.
  Future<void> close() async {
    await autosave.flush();
  }

  void _scheduleSave() {
    final dohan = _dohan;
    final id = _artworkId;
    if (dohan == null || id == null) return;
    autosave.schedule(Artwork(
      id: id,
      dohanId: dohan.meta.id,
      fills: _state.fills.toJson(),
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  @override
  void dispose() {
    // dispose 는 동기라 flush 를 기다릴 수 없다. 그렇다고 autosave 를 그냥
    // 버리면 예약돼 있던 마지막 탭이 조용히 사라진다 — 아이가 칠하자마자
    // 화면을 닫는 것이 정확히 그 상황이다. 쓰기를 먼저 걸어 두고, 그것이 끝난
    // 뒤에 autosave 를 정리한다. flush() 는 던지지 않으므로 이 체인은 안전하다.
    unawaited(autosave.flush().then((_) => autosave.dispose()));
    super.dispose();
  }
}
