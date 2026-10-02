import 'dart:async';
import 'dart:ui' as ui;
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
import 'brush_painter.dart';
import 'brush_state.dart';
import 'canvas_transform.dart';
import 'fill_state.dart';
import 'paintable_mask.dart';
import 'sticker_state.dart';

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

  ui.Image? _mask;

  /// 이번 지우개 손짓에서 벗길 영역과 그 이전 색.
  final Map<int, Color?> _erasing = {};

  ToolKind _tool = ToolKind.bucket;
  Shade _shade = Shade.base;
  int _colorIndex = 0;

  /// 유아 모드의 "연속 한 번" 제한을 세는 값. 새로 무언가를 하면 0 이 된다.
  int _undosSinceChange = 0;

  /// 끌기 시작 시점의 스티커. 손을 뗄 때 이것과 비교해 명령 하나를 만든다.
  Sticker? _dragBefore;

  /// 같은 밀리초 안에 스티커가 여러 번 붙어도 instanceId 가 겹치지 않도록 하는
  /// 카운터. 이 환경의 시계 분해능은 마이크로초 단위가 아니다 — 실측으로
  /// `DateTime.now().microsecondsSinceEpoch` 를 연달아 불러도 같은 값이
  /// 나온다. 타임스탬프만 쓰면 빠르게 두 번 붙인 스티커가 같은 instanceId 를
  /// 받아, 하나를 지울 때 엉뚱한 자리의 것이 지워진다.
  int _stickerSeq = 0;

  DohanPackage? get dohan => _dohan;
  FillState get fills => _state.fills;
  ArtworkState get state => _state;

  /// 칠할 수 있는 픽셀만 불투명한 마스크. 브러시 합성에 쓴다.
  ui.Image? get paintableMask => _mask;
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
    List<Sticker> stickers = const [],
    Uint8List? brushPng,
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
    _mask?.dispose();
    _mask = await buildPaintableMask(dohan.regions);
    _artworkId = artworkId;
    _undo.clear();
    _state.clear();
    if (existing != null) _state.fills.loadJson(existing.fills);

    for (final s in stickers) {
      _state.stickers.insertAt(_state.stickers.stickers.length, s);
    }

    if (brushPng != null) {
      final restored = await _decodePng(brushPng);
      // 두 번째 await 다. 그 사이에 또 열렸으면 이 결과는 버린다 — 위의
      // 세대 가드와 같은 이유이고, 버리기 전에 해제해야 이미지가 샌다.
      if (generation != _openGeneration) {
        restored.dispose();
        return;
      }
      _state.brush.base = restored;
    }

    // 복원한 상태가 이미 디스크에 있는 것이므로, 손대지 않은 작품이 첫 저장에서
    // 헛되이 굽지 않도록 여기서 기준선을 잡는다. 반드시 복원 **뒤**다.
    autosave.markBrushWritten(_state.brush.revision);
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

  double get _strokeWidth => switch (_tool) {
        ToolKind.crayon => kCrayonWidth,
        ToolKind.brush => kBrushWidth,
        ToolKind.eraser => kEraserWidth,
        _ => kCrayonWidth,
      };

  BrushKind? get _strokeKind => switch (_tool) {
        ToolKind.crayon => BrushKind.crayon,
        ToolKind.brush => BrushKind.brush,
        ToolKind.eraser => BrushKind.eraser,
        _ => null,
      };

  void beginStroke(Offset canvasPoint) {
    if (_tool == ToolKind.eraser) {
      final hit = _state.stickers.topAt(canvasPoint);
      if (hit != null) {
        // 스티커를 떼려던 손짓이 밑의 그림까지 지우면 안 된다. 여기서 끝낸다.
        final index = _state.stickers.indexOf(hit.instanceId);
        _undo.push(
          StickerCommand(index: index, before: hit, after: null),
          _state,
        );
        _afterChange();
        return;
      }
    }

    final kind = _strokeKind;
    if (kind == null || _dohan == null) return;

    _erasing.clear();
    _state.brush.live = Stroke(
      kind: kind,
      color: selectedColor,
      width: _strokeWidth,
      points: [canvasPoint],
    );
    _collectErase(canvasPoint);
    notifyListeners();
  }

  void extendStroke(Offset canvasPoint) {
    final live = _state.brush.live;
    if (live == null) return;

    // 지우개 판정은 **점을 버리기 전에** 한다. 점을 버리는 것은 획을 매끄럽게
    // 하려는 것이지 "거기를 지나가지 않았다"는 뜻이 아니다. 뒤에 두면 좁은
    // 캔버스에서 지나간 영역이 통째로 안 지워진다.
    _collectErase(canvasPoint);

    // 점이 촘촘해도 그림은 달라지지 않고 덮임 판정만 느려진다.
    if ((live.points.last - canvasPoint).distance < 4) return;
    // Stroke 는 불변이다. 목록에 add 하지 말고 새 획으로 갈아끼운다 —
    // const 로 만들어진 획이면 add 가 끌기 도중에 터진다.
    _state.brush.live = live.withPoint(canvasPoint);
    notifyListeners();
  }

  void endStroke() {
    final live = _state.brush.live;
    if (live == null) return;
    _state.brush.live = null;

    final commands = <Command>[StrokeCommand(live)];
    for (final e in _erasing.entries) {
      commands.add(FillCommand(regionId: e.key, before: e.value, after: null));
    }
    _erasing.clear();

    // 지우개 한 손짓이 획 하나와 채움 여러 개를 만들 수 있다. 아이는 되돌리기
    // 한 번에 그 손짓 전체가 돌아오기를 기대한다.
    _undo.push(
      commands.length == 1 ? commands.first : BatchCommand(commands),
      _state,
    );
    // 태스크 11 이 만든 공통 처리. 되돌리기 예산 복구 + 저장 예약 + 다시 그리기를
    // 한 자리에 모아 둔 것이라, 도구를 추가할 때 하나를 빠뜨릴 수 없다.
    _afterChange();
  }

  /// 지우개가 지나간 자리에서 벗길 채움을 모은다.
  ///
  /// 브러시 잉크가 그 점을 덮고 있으면 채움은 건드리지 않는다 — "손가락 밑의
  /// 맨 위 것"을 지우는 것이므로, 잉크가 위에 있으면 잉크만 지워진다.
  void _collectErase(Offset p) {
    if (_tool != ToolKind.eraser) return;
    final dohan = _dohan;
    if (dohan == null) return;
    if (_state.brush.hasInkAt(p)) return;

    final id = regionAt(dohan.regions, p);
    if (id < kRegionFirstFillable) return;
    if (_erasing.containsKey(id)) return;

    final before = _state.fills.fillOf(id);
    if (before == null) return;
    _erasing[id] = before;
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
    autosave.schedule(
      Artwork(
        id: id,
        dohanId: dohan.meta.id,
        fills: _state.fills.toJson(),
        updatedAt: DateTime.now().toUtc(),
      ),
      stickers: _state.stickers.stickers,
      brushRevision: _state.brush.revision,
      bakeBrush: _bakeBrush,
    );
  }

  /// 브러시 레이어를 PNG 로 굽는다. 자동 저장이 **실제로 쓸 때만** 부른다 —
  /// 실측 53ms 라 탭마다 하면 끊긴다.
  ///
  /// 빈 브러시라도 굽는다. `null` 은 "파일을 건드리지 마라"는 뜻이지 "비었다"는
  /// 뜻이 아니다 — 전부 지운 뒤 null 을 돌려주면 낡은 brush.png 가 그대로 남아,
  /// 앱을 껐다 켠 아이에게 지운 자국이 되살아난다. 빈 브러시는 완전히 투명한
  /// PNG 로 구워지며, 그런 이미지는 거의 압축되어 저장 비용이 미미하다.
  Future<Uint8List?> _bakeBrush() async {
    final dohan = _dohan;
    if (dohan == null) return null;

    final size = dohan.regions.width;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    BrushPainter.paint(
      canvas,
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      _state.brush,
      _mask,
    );
    final picture = rec.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    // ByteData 는 더 큰 버퍼의 조각일 수 있다. .buffer 를 그대로 쓰면
    // offsetInBytes 를 무시해 엉뚱한 자리에서 읽는다 — 계획 2 에서 에셋 로딩에
    // 같은 실수를 했다가 리뷰가 잡았다.
    return Uint8List.sublistView(data);
  }

  Sticker? stickerAt(Offset canvasPoint) =>
      _state.stickers.topAt(canvasPoint);

  /// 서랍에서 고른 스티커를 캔버스 한가운데에 놓는다.
  ///
  /// 놓는 동작이 실패할 수 없다는 것이 핵심이다 — 아이가 손을 어디서 떼든
  /// 스티커는 이미 화면에 있고, 마음에 안 들면 끌면 된다.
  void addSticker(String stickerId) {
    final dohan = _dohan;
    if (dohan == null) return;

    final centre = dohan.regions.width / 2;
    final sticker = Sticker(
      instanceId:
          '${DateTime.now().microsecondsSinceEpoch}-${_stickerSeq++}',
      stickerId: stickerId,
      x: centre,
      y: centre,
    );

    _undo.push(
      StickerCommand(
        index: _state.stickers.stickers.length,
        before: null,
        after: sticker,
      ),
      _state,
    );
    _afterChange();
  }

  void beginStickerDrag(Offset canvasPoint) {
    _dragBefore = _state.stickers.topAt(canvasPoint);
  }

  /// 손가락을 따라 바로 움직인다. 되돌리기 스택은 건드리지 않는다.
  void updateStickerDrag({
    required double x,
    required double y,
    double? scale,
  }) {
    final before = _dragBefore;
    if (before == null) return;
    final index = _state.stickers.indexOf(before.instanceId);
    if (index < 0) return;

    _state.stickers
        .replaceAt(index, before.copyWith(x: x, y: y, scale: scale));
    notifyListeners();
  }

  void endStickerDrag() {
    final before = _dragBefore;
    _dragBefore = null;
    if (before == null) return;

    final index = _state.stickers.indexOf(before.instanceId);
    if (index < 0) return;

    final after = _state.stickers.stickers[index];
    if (after.x == before.x &&
        after.y == before.y &&
        after.scale == before.scale) {
      return; // 제자리에서 손을 뗐다
    }

    // 스택에는 출발 → 도착 하나만 쌓는다. 중간 프레임 수백 개는 아이에게
    // 되돌릴 단계가 아니다. 명령이 제 손으로 적용하도록 먼저 되돌려 둔다.
    _state.stickers.replaceAt(index, before);
    _undo.push(
      StickerCommand(index: index, before: before, after: after),
      _state,
    );
    _afterChange();
  }

  @override
  void dispose() {
    _mask?.dispose();
    _mask = null;
    _state.brush.base?.dispose();
    _state.brush.base = null;
    // dispose 는 동기라 flush 를 기다릴 수 없다. 그렇다고 autosave 를 그냥
    // 버리면 예약돼 있던 마지막 탭이 조용히 사라진다 — 아이가 칠하자마자
    // 화면을 닫는 것이 정확히 그 상황이다. 쓰기를 먼저 걸어 두고, 그것이 끝난
    // 뒤에 autosave 를 정리한다. flush() 는 던지지 않으므로 이 체인은 안전하다.
    unawaited(autosave.flush().then((_) => autosave.dispose()));
    super.dispose();
  }
}

Future<ui.Image> _decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
