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
import 'canvas_transform.dart';
import 'fill_state.dart';

/// 색칠 화면의 상태를 한곳에 묶는다.
///
/// 위젯을 모른다 — 탭 좌표는 이미 캔버스 좌표로 바뀐 것을 받는다. 화면 없이
/// 테스트할 수 있어야 색칠 규칙을 위젯 테스트의 복잡도 없이 잠글 수 있다.
class ColoringController extends ChangeNotifier {
  final DohanSource source;
  final Autosave autosave;

  ColoringController({required this.source, required this.autosave});

  DohanPackage? _dohan;
  String? _artworkId;
  final ArtworkState _state = ArtworkState();
  final UndoStack _undo = UndoStack();
  Color _selected = const Color(0xFFEF7586);
  int _openGeneration = 0;

  DohanPackage? get dohan => _dohan;
  FillState get fills => _state.fills;
  ArtworkState get state => _state;
  Color get selectedColor => _selected;
  bool get canUndo => _undo.canUndo;
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

  void pickColor(Color color) {
    _selected = color;
    notifyListeners();
  }

  /// 캔버스 좌표를 칠한다. 실제로 바뀐 것이 있으면 true.
  bool tapAt(Offset canvasPoint) {
    final dohan = _dohan;
    if (dohan == null) return false;

    final id = regionAt(dohan.regions, canvasPoint);
    if (id < kRegionFirstFillable) return false;

    final before = _state.fills.fillOf(id);
    if (before == _selected) return false;

    _undo.push(
      // const 를 붙이면 안 된다 — id·before·_selected 가 전부 런타임 값이라
      // "Arguments of a constant creation must be constant expressions" 로
      // 컴파일이 깨진다. FillCommand 의 생성자가 const 인 것과는 별개다.
      FillCommand(regionId: id, before: before, after: _selected),
      _state,
    );
    _scheduleSave();
    notifyListeners();
    return true;
  }

  bool undo() {
    if (!_undo.undo(_state)) return false;
    _scheduleSave();
    notifyListeners();
    return true;
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
