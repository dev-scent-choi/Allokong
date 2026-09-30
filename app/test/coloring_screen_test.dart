import 'dart:io';
import 'dart:typed_data';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_controller.dart';
import 'package:kkumul/coloring/sticker_state.dart';
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/gallery/autosave.dart';
import 'package:kkumul/ui/coloring_screen.dart';
import 'package:kkumul/ui/palette_bar.dart';
import 'package:kkumul/ui/palette_shades.dart';

class FakeDohanSource implements DohanSource {
  @override
  Future<List<String>> listIds() async => ['fake'];

  @override
  Future<DohanPackage> load(String id) async {
    const n = 64;
    final ids = Uint16List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        ids[y * n + x] = x < n ~/ 2 ? 2 : 3;
      }
    }
    return DohanPackage(
      meta: DohanMeta(
        id: 'fake',
        title: '가짜',
        category: 'animal',
        source: 'bundled',
        canvasSize: const [n, n],
        regionCount: 2,
        difficulty: 1,
        suggestedPalette: const [],
        regionAnchors: const {},
        createdAt: DateTime.utc(2026, 9, 25),
      ),
      lineart: img.Image(width: n, height: n, numChannels: 4),
      regions: RegionMap(n, n, ids),
    );
  }
}

void main() {
  late Directory root;
  late ColoringController controller;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('kkumul_ui_');
    controller = ColoringController(
      source: FakeDohanSource(),
      autosave: _NoopAutosave(root),
    );
    await controller.open(dohanId: 'fake', artworkId: 'w1');
  });
  tearDown(() async {
    await controller.close();
    controller.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('팔레트에서 색을 고르면 컨트롤러에 반영된다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final swatches = find.byType(ColorSwatchButton);
    expect(swatches, findsNWidgets(8), reason: '유아 팔레트는 8색이다');

    await tester.tap(swatches.at(4));
    await tester.pump();

    expect(controller.selectedColor, paletteShades[Shade.base]![4]);
  });

  testWidgets('캔버스를 탭하면 그 영역이 칠해진다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final canvas = find.byKey(const ValueKey('coloring-canvas'));
    final box = tester.getRect(canvas);

    // 왼쪽 절반 = 영역 2
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();

    expect(controller.fills.fillOf(2), isNotNull);
    expect(controller.fills.fillOf(3), isNull);
  });

  testWidgets('되돌리기 버튼은 되돌릴 것이 있을 때만 눌린다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final undo = find.byKey(const ValueKey('undo-button'));
    expect(tester.widget<IconButton>(undo).onPressed, isNull,
        reason: '처음에는 되돌릴 것이 없다');

    final box = tester.getRect(find.byKey(const ValueKey('coloring-canvas')));
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();

    expect(tester.widget<IconButton>(undo).onPressed, isNotNull);

    await tester.tap(undo);
    await tester.pump();

    expect(controller.fills.filledCount, 0);
  });

  testWidgets('터치 타겟이 64dp 이상이다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    for (final e in find.byType(ColorSwatchButton).evaluate()) {
      final size = tester.getSize(find.byWidget(e.widget));
      expect(size.width, greaterThanOrEqualTo(64));
      expect(size.height, greaterThanOrEqualTo(64));
    }

    // 되돌리기 버튼도 같은 기준을 지켜야 한다. IconButton 의 기본값은 48 이라
    // 그냥 두면 조용히 어긴다.
    final undo = tester.getSize(find.byKey(const ValueKey('undo-button')));
    expect(undo.width, greaterThanOrEqualTo(64));
    expect(undo.height, greaterThanOrEqualTo(64));
  });

  testWidgets('좁은 화면에서도 여덟 색이 모두 보이고 제스처 영역에 가리지 않는다',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final swatches = find.byType(ColorSwatchButton);
    expect(swatches, findsNWidgets(8));

    for (final e in swatches.evaluate()) {
      final rect = tester.getRect(find.byWidget(e.widget));
      expect(rect.width, greaterThanOrEqualTo(64));
      expect(rect.height, greaterThanOrEqualTo(64));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320),
          reason: '화면 밖으로 밀려난 색은 아이에게 없는 색이다');
      expect(rect.bottom, lessThanOrEqualTo(640 - 34),
          reason: '제스처 영역에 걸치면 색 대신 홈 제스처가 먹는다');
    }
  });

  testWidgets('앱이 물러나면 예약된 저장을 마무리한다', (tester) async {
    final autosave = _RecordingAutosave(root);
    final lifecycleController = ColoringController(
      source: FakeDohanSource(),
      autosave: autosave,
    );
    await lifecycleController.open(dohanId: 'fake', artworkId: 'w9');
    addTearDown(lifecycleController.dispose);

    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: lifecycleController),
    ));
    await tester.pumpAndSettle();

    // ColoringController.open() 이 갈아타기 전에 이전 작품을 안전하게 쓰려고
    // 자체적으로 flush() 를 한 번 부른다(태스크 9) — 그래서 여기서는 0 이
    // 아니라 "지금까지 부른 횟수"를 기준선으로 잡는다. 이 테스트가 보는 것은
    // 생명주기 콜백이 그 위에 flush() 를 더 부르는지다.
    final before = autosave.flushCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(autosave.flushCount, greaterThan(before),
        reason: '아이가 앱을 떠나면 기다리지 말고 바로 써야 한다');
  });
}

/// 위젯 테스트는 저장 경로를 건드리지 않는다.
///
/// 디바운스 타이머를 살려 두면 `flutter_test` 가 "A Timer is still pending" 으로
/// 실패하고, 그렇다고 `pump(Duration)` 으로 태우면 fake_async 아래에서 테스트가
/// 통째로 멈춘다(저장소를 메모리 구현으로 바꿔도 멈추므로 디스크 I/O 탓이 아니다).
/// 저장 동작은 `autosave_test.dart`(6개)와 `coloring_controller_test.dart`(13개)가
/// 이미 덮는다. 여기서 볼 것은 화면 배선이다.
class _NoopAutosave extends Autosave {
  _NoopAutosave(Directory root) : super(repository: ArtworkRepository(root));

  @override
  void schedule(
    Artwork artwork, {
    List<Sticker> stickers = const [],
    int brushRevision = 0,
    BrushBaker? bakeBrush,
  }) {}
}

/// 생명주기 배선만 본다. `flush()` 가 실제로 불렸는지만 기록하고 디스크는
/// 건드리지 않는다 — 타이머도 I/O 도 없어야 위젯 테스트가 멈추지 않는다.
class _RecordingAutosave extends Autosave {
  _RecordingAutosave(Directory root) : super(repository: ArtworkRepository(root));

  int flushCount = 0;

  @override
  void schedule(
    Artwork artwork, {
    List<Sticker> stickers = const [],
    int brushRevision = 0,
    BrushBaker? bakeBrush,
  }) {}

  @override
  Future<void> flush() async {
    flushCount++;
  }
}
