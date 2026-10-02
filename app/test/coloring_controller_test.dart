import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/brush_state.dart';
import 'package:kkumul/coloring/coloring_controller.dart';
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/gallery/autosave.dart';
import 'package:kkumul/settings/settings.dart';
import 'package:kkumul/ui/palette_shades.dart';
import 'package:image/image.dart' as img;

/// 좌/우 두 영역만 있는 가짜 도안. 에셋 없이 컨트롤러를 시험한다.
class FakeDohanSource implements DohanSource {
  @override
  Future<List<String>> listIds() async => ['fake'];

  @override
  Future<DohanPackage> load(String id) async {
    const w = 4, h = 2;
    final ids = Uint16List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        ids[y * w + x] = x < 2 ? 2 : 3;
      }
    }
    return DohanPackage(
      meta: DohanMeta(
        id: 'fake',
        title: '가짜',
        category: 'animal',
        source: 'bundled',
        canvasSize: const [w, h],
        regionCount: 2,
        difficulty: 1,
        suggestedPalette: const ['#ef7586'],
        regionAnchors: const {},
        createdAt: DateTime.utc(2026, 9, 25),
      ),
      lineart: img.Image(width: w, height: h, numChannels: 4),
      regions: RegionMap(w, h, ids),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ColoringController c;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('kkumul_ctl_');
    c = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(
        repository: ArtworkRepository(root),
        debounce: const Duration(milliseconds: 20),
      ),
      ageMode: AgeMode.child,
    );
    await c.open(dohanId: 'fake', artworkId: 'w1');
  });
  tearDown(() async {
    await c.close();
    root.deleteSync(recursive: true);
  });

  test('도안을 열면 준비 상태가 된다', () {
    expect(c.isReady, isTrue);
    expect(c.dohan!.meta.id, 'fake');
    expect(c.fills.filledCount, 0);
  });

  test('탭하면 그 영역이 선택한 색으로 칠해진다', () {
    c.pickColorIndex(0);

    expect(c.tapAt(const Offset(0.5, 0.5)), isTrue);

    expect(c.fills.fillOf(2), const Color(0xFFEF7586));
    expect(c.fills.fillOf(3), isNull);
  });

  test('영역마다 다른 색을 칠할 수 있다', () {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.pickColorIndex(3);
    c.tapAt(const Offset(3.5, 0.5));

    expect(c.fills.fillOf(2), const Color(0xFFEF7586));
    expect(c.fills.fillOf(3), const Color(0xFF6CAEE0));
  });

  test('같은 색을 다시 칠하면 아무 일도 없다', () {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));

    expect(c.tapAt(const Offset(0.5, 0.5)), isFalse,
        reason: '되돌리기 스택을 의미 없이 채우지 않는다');
    expect(c.canUndo, isTrue);
  });

  test('캔버스 밖을 누르면 아무 일도 없다', () {
    c.pickColorIndex(0);

    expect(c.tapAt(const Offset(-5, -5)), isFalse);
    expect(c.fills.filledCount, 0);
    expect(c.canUndo, isFalse);
  });

  test('되돌리면 직전 상태로 간다', () {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));

    expect(c.undo(), isTrue);

    expect(c.fills.fillOf(2), isNull);
    expect(c.canUndo, isFalse);
  });

  test('칠하면 자동 저장이 예약되고, 닫으면 파일이 남는다', () async {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));

    await c.close();

    final saved = await ArtworkRepository(root).load('w1');
    expect(saved, isNotNull);
    expect(saved!.dohanId, 'fake');
    expect(saved.fills[2], const Color(0xFFEF7586).toARGB32());
  });

  test('저장된 작품을 열면 칠한 것이 되살아난다', () async {
    final restored = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(repository: ArtworkRepository(root)),
    );
    addTearDown(restored.close);

    await restored.open(
      dohanId: 'fake',
      artworkId: 'w2',
      existing: Artwork(
        id: 'w2',
        dohanId: 'fake',
        fills: {2: const Color(0xFF63B98B).toARGB32()},
        updatedAt: DateTime.utc(2026, 9, 25),
      ),
    );

    expect(restored.fills.fillOf(2), const Color(0xFF63B98B));
    expect(restored.canUndo, isFalse, reason: '불러온 상태는 되돌릴 대상이 아니다');
  });

  test('다른 도안으로 갈아타도 앞 작품의 마지막 칠이 남는다', () async {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));

    // 디바운스가 끝나기 전에 갈아탄다 — 아이가 칠하자마자 다른 도안을 고르는 경우다.
    await c.open(dohanId: 'fake', artworkId: 'w2');
    c.pickColorIndex(3);
    c.tapAt(const Offset(0.5, 0.5));
    await c.close();

    final repo = ArtworkRepository(root);
    expect((await repo.load('w1'))!.fills[2], const Color(0xFFEF7586).toARGB32(),
        reason: '갈아타기 전에 칠한 것이 사라지면 안 된다');
    expect((await repo.load('w2'))!.fills[2], const Color(0xFF6CAEE0).toARGB32());
  });

  test('close 없이 dispose 해도 마지막 칠이 남는다', () async {
    final one = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(
        repository: ArtworkRepository(root),
        // 디바운스를 길게 잡아, 쓰였다면 그것은 dispose 가 쓴 것이다.
        debounce: const Duration(seconds: 30),
      ),
    );
    await one.open(dohanId: 'fake', artworkId: 'w3');
    one.pickColorIndex(4);
    one.tapAt(const Offset(0.5, 0.5));

    one.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final saved = await ArtworkRepository(root).load('w3');
    expect(saved, isNotNull, reason: '아이가 칠하자마자 화면을 닫은 경우다');
    expect(saved!.fills[2], const Color(0xFF63B98B).toARGB32());
  });

  test('덧칠한 뒤 되돌리면 그 전 색으로 돌아간다', () {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.pickColorIndex(3);
    c.tapAt(const Offset(0.5, 0.5));

    expect(c.undo(), isTrue);

    expect(c.fills.fillOf(2), const Color(0xFFEF7586),
        reason: 'null 이 아니라 직전 색으로 돌아와야 한다');
  });

  test('탭만 하고 두면 디바운스가 끝난 뒤 저장된다', () async {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));

    // close() 를 부르지 않는다 — 타이머가 스스로 쓰는지 본다.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final saved = await ArtworkRepository(root).load('w1');
    expect(saved, isNotNull);
    expect(saved!.fills[2], const Color(0xFFEF7586).toARGB32());
  });

  test('다른 도안을 열면 앞선 되돌리기 기록이 남지 않는다', () async {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    expect(c.canUndo, isTrue);

    await c.open(dohanId: 'fake', artworkId: 'w4');

    expect(c.canUndo, isFalse, reason: '새로 연 도안은 앞 도안을 되돌릴 수 없다');
    expect(c.fills.filledCount, 0);
  });

  test('처음 도구는 양동이다', () {
    expect(c.tool, ToolKind.bucket);
  });

  test('도구를 고르면 바뀐다', () {
    c.selectTool(ToolKind.crayon);
    expect(c.tool, ToolKind.crayon);
  });

  test('색은 자리로 고르고 명도가 곱해진다', () {
    c.pickColorIndex(4);
    expect(c.colorIndex, 4);
    expect(c.selectedColor, paletteShades[Shade.base]![4]);
  });

  test('팔레트 범위 밖 자리는 무시한다', () {
    c.pickColorIndex(3);
    c.pickColorIndex(99);
    expect(c.colorIndex, 3, reason: '범위 밖이면 그대로 둔다');
    c.pickColorIndex(-1);
    expect(c.colorIndex, 3);
  });

  test('명도를 누르면 고른 자리는 그대로고 색만 바뀐다', () {
    c.pickColorIndex(4);
    c.cycleShade();

    expect(c.colorIndex, 4, reason: '아이가 고른 자리는 유지된다');
    expect(c.shade, Shade.dark, reason: 'base 다음은 dark');
    expect(c.selectedColor, paletteShades[Shade.dark]![4]);
  });

  test('명도는 한 바퀴 돈다', () {
    c.cycleShade();
    c.cycleShade();
    expect(c.shade, Shade.light);
    c.cycleShade();
    expect(c.shade, Shade.base);
  });

  test('양동이가 아니면 탭해도 칠해지지 않는다', () {
    c.selectTool(ToolKind.crayon);
    expect(c.tapAt(const Offset(0.5, 0.5)), isFalse,
        reason: '크레용은 끌어서 그리는 도구다');
    expect(c.fills.filledCount, 0);
  });

  test('유아 모드는 연속 한 번만 되돌린다', () {
    c.ageMode = AgeMode.toddler;
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.tapAt(const Offset(3.5, 0.5));

    expect(c.undo(), isTrue);
    expect(c.undo(), isFalse, reason: '상위 스펙 9장 — 유아는 한 단계');
    expect(c.canUndo, isFalse, reason: '버튼도 꺼져야 한다');
  });

  test('유아 모드도 새로 칠하면 다시 한 번 되돌릴 수 있다', () {
    c.ageMode = AgeMode.toddler;
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.undo();
    expect(c.undo(), isFalse);

    c.tapAt(const Offset(3.5, 0.5));
    expect(c.canUndo, isTrue);
    expect(c.undo(), isTrue);
  });

  test('아동 모드는 계속 되돌린다', () {
    c.ageMode = AgeMode.child;
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.tapAt(const Offset(3.5, 0.5));

    expect(c.undo(), isTrue);
    expect(c.undo(), isTrue);
    expect(c.undo(), isFalse, reason: '더 없어서 false 다');
  });

  test('크레용으로 끌면 획이 남는다', () {
    c.selectTool(ToolKind.crayon);
    c.beginStroke(const Offset(0.5, 0.5));
    c.extendStroke(const Offset(3.5, 0.5));
    c.endStroke();

    expect(c.state.brush.strokes, hasLength(1));
    expect(c.state.brush.strokes.first.kind, BrushKind.crayon);
    expect(c.state.brush.live, isNull, reason: '손을 떼면 live 가 비워진다');
  });

  test('그리는 중에는 live 에 들어 있다', () {
    c.selectTool(ToolKind.brush);
    c.beginStroke(const Offset(0.5, 0.5));
    expect(c.state.brush.live, isNotNull);
    expect(c.state.brush.strokes, isEmpty, reason: '아직 명령이 아니다');
    c.endStroke();
    expect(c.state.brush.strokes, hasLength(1));
  });

  test('획을 되돌리면 사라진다', () {
    c.selectTool(ToolKind.crayon);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();

    expect(c.undo(), isTrue);
    expect(c.state.brush.strokes, isEmpty);
  });

  test('너무 촘촘한 점은 버린다', () {
    // 점이 촘촘해도 그림은 달라지지 않고 덮임 판정만 느려진다.
    c.selectTool(ToolKind.brush);
    c.beginStroke(const Offset(0, 0));
    c.extendStroke(const Offset(1, 0));
    c.extendStroke(const Offset(2, 0));
    c.endStroke();

    expect(c.state.brush.strokes.first.points, hasLength(1),
        reason: '4px 미만은 버린다');
  });

  test('양동이일 때는 끌어도 획이 생기지 않는다', () {
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();
    expect(c.state.brush.strokes, isEmpty);
  });

  test('지우개로 칠한 영역을 문지르면 색이 벗겨진다', () {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    expect(c.fills.fillOf(2), isNotNull);

    c.selectTool(ToolKind.eraser);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();

    expect(c.fills.fillOf(2), isNull);
  });

  test('지우개 한 손짓은 되돌리기 한 번에 전부 돌아온다', () {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.tapAt(const Offset(3.5, 0.5));
    expect(c.fills.filledCount, 2);

    c.selectTool(ToolKind.eraser);
    c.beginStroke(const Offset(0.5, 0.5));
    c.extendStroke(const Offset(3.5, 0.5));
    c.endStroke();
    expect(c.fills.filledCount, 0);

    expect(c.undo(), isTrue);
    expect(c.fills.filledCount, 2, reason: '묶음이므로 한 번에 둘 다 돌아온다');
  });

  test('브러시 잉크가 있는 자리는 채움을 벗기지 않는다', () {
    // "손가락 밑의 맨 위 것을 지운다" — 잉크가 위에 있으면 잉크만 지운다.
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));

    c.selectTool(ToolKind.crayon);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();

    c.selectTool(ToolKind.eraser);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();

    expect(c.fills.fillOf(2), isNotNull,
        reason: '잉크가 덮고 있었으므로 채움은 남는다');
  });

  test('도안을 열면 마스크가 만들어진다', () {
    expect(c.paintableMask, isNotNull);
    expect(c.paintableMask!.width, 4, reason: '가짜 도안이 4x2 다');
  });

  test('브러시를 전부 지우면 저장된 브러시도 비워진다', () async {
    // null 은 "파일을 건드리지 마라"라는 뜻이다. 빈 브러시에 null 을 돌려주면
    // 낡은 brush.png 가 남아, 앱을 껐다 켠 아이에게 지운 자국이 되살아난다.
    c.selectTool(ToolKind.crayon);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();
    await c.close();

    final afterDraw = await ArtworkRepository(root).loadBrushPng('w1');
    expect(afterDraw, isNotNull, reason: '그렸으니 파일이 생긴다');

    expect(c.undo(), isTrue);
    await c.close();

    final afterUndo = await ArtworkRepository(root).loadBrushPng('w1');
    expect(afterUndo, isNotNull, reason: '파일은 남되 내용이 바뀌어야 한다');
    expect(afterUndo, isNot(afterDraw),
        reason: '지운 뒤의 브러시는 그리기 전과 달라야 한다');
  });
}
