import 'dart:io';
import 'dart:typed_data';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_route.dart' show ColoringSession;
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/play/play_screen.dart';
import 'package:kkumul/settings/settings.dart';
import 'package:kkumul/shell/bottom_nav.dart';
import 'package:kkumul/shell/placeholder_screen.dart';
import 'package:kkumul/shell/shell_screen.dart';
import 'package:kkumul/ui/art_tile.dart';
import 'package:kkumul/ui/tool_bar.dart';

/// 칠할 수 있는 64x64 도안 하나. 색칠 화면까지 열어 보는 테스트가 쓴다.
class FakeLibrary implements DohanSource {
  static const _ids = ['animal-a', 'car-a', 'dino-a', 'shape-a'];

  @override
  Future<List<String>> listIds() async => _ids;

  @override
  Future<DohanMeta> loadMeta(String id) async => DohanMeta(
        id: id,
        title: '제목 $id',
        category: id.split('-').first == 'dino' ? 'dinosaur' : id.split('-').first,
        source: 'bundled',
        canvasSize: const [64, 64],
        regionCount: 2,
        difficulty: 1,
        suggestedPalette: const [],
        regionAnchors: const {},
        createdAt: DateTime.utc(2026, 10, 6),
      );

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
      meta: await loadMeta(id),
      lineart: img.Image(width: n, height: n, numChannels: 4),
      regions: RegionMap(n, n, ids),
    );
  }
}

void main() {
  late Directory root;
  late ArtworkRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_shell_');
    repository = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Widget host({AgeMode ageMode = AgeMode.toddler}) => MaterialApp(
        home: ShellScreen(
          source: FakeLibrary(),
          repository: repository,
          settingsStore: SettingsStore(root),
          initialAgeMode: ageMode,
        ),
      );

  Future<void> settle(WidgetTester tester, [Finder? until]) async {
    // **`pumpAndSettle` 을 쓰지 않는다.** 읽는 동안 도는
    // `CircularProgressIndicator` 가 프레임을 끝없이 예약해서 영영 멎지
    // 않고, 기본 타임아웃 10분까지 교착한다 — 태스크 5 에서 실제로 그랬다.
    //
    // 엔진 콜백은 FakeAsync 아래에서 완료되지 않으므로 실제 존에서
    // 기다리며 펌프한다. 기다릴 조건이 있으면 주는 편이 빠르고 정확하다.
    for (var i = 0; i < 200; i++) {
      if (until != null && until.evaluate().isNotEmpty) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      // **시간을 주어 펌프한다.** 인자 없는 pump() 는 시계를 움직이지
      // 않아 라우트 전환이 영영 안 끝난다 — 태스크 5 에서 실제로 그랬다.
      await tester.pump(const Duration(milliseconds: 25));
      if (until == null && i >= 59) break; // 조건이 없으면 1.5초로 끝낸다
    }
    // 조건이 섰어도 전환은 아직 날아가는 중일 수 있다. 끝까지 민다.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('놀기로 시작하고 탭을 오갈 수 있다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.text('바로 시작'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);
    expect(find.byKey(const ValueKey('gallery-empty')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-me')));
    await settle(tester);
    expect(find.byKey(const ValueKey('age-child')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-create')));
    await settle(tester);
    expect(find.byType(PlaceholderScreen), findsOneWidget);
  });

  testWidgets('색칠 화면에는 내비가 없다', (tester) async {
    // 설계 스펙 2.1 — 내비를 넣으면 캔버스가 350 에서 286dp 로 줄어
    // 본문의 절반 아래가 된다.
    await tester.pumpWidget(host());
    await settle(tester);
    expect(find.byType(BottomNav), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('today-tile')));
    await settle(tester);

    expect(find.byKey(const ValueKey('coloring-canvas')), findsOneWidget);
    // 셸의 라우트는 가려져도 트리에 남아 있으므로 전역 findsNothing 은
    // 모호하다. 색칠 화면 **안에** 내비가 없다는 것을 직접 본다.
    expect(
      find.descendant(
        of: find.byType(ColoringSession),
        matching: find.byType(BottomNav),
      ),
      findsNothing,
    );

    await tester.tap(find.text('완성'));
    await settle(tester);

    expect(find.byType(BottomNav), findsOneWidget, reason: '돌아오면 다시 있다');
  });

  testWidgets('놀기에서 그린 그림이 모아보기에 나타난다', (tester) async {
    // 탭이 IndexedStack 안에 살아 있어서 스스로 다시 지어지지 않는다.
    // 셸이 다시 읽으라고 알려 주지 않으면 영영 안 보인다.
    await tester.pumpWidget(host());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('today-tile')));
    await settle(tester);
    final box = tester.getRect(find.byKey(const ValueKey('coloring-canvas')));
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();
    await tester.tap(find.text('완성'));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);

    expect(find.byType(ArtTile), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-empty')), findsNothing);
  });

  testWidgets('탭을 오가도 스크롤 위치가 유지된다', (tester) async {
    // 아이가 모아보기를 보다 돌아왔을 때 놀기가 처음으로 튀면 안 된다.
    await tester.pumpWidget(host());
    await settle(tester);

    // 놀기의 **바깥** 목록을 직접 짚는다. `find.descendant` 만 쓰면
    // 카테고리 격자까지 잡혀 "Found 2 widgets" 로 던진다 — 격자는
    // 스스로 스크롤하지 않지만 Scrollable 이기는 하다.
    final playList = find
        .descendant(
          of: find.byType(PlayScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    // playList 가 이미 Scrollable 자신이라 Scrollable.of 는 위쪽만 찾아 던진다.
    double playOffset() => tester.state<ScrollableState>(playList).position.pixels;

    await tester.drag(playList, const Offset(0, -200));
    await settle(tester);
    final scrolled = playOffset();
    expect(scrolled, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nav-play')));
    await settle(tester);

    expect(playOffset(), scrolled, reason: '처음으로 튀면 안 된다');
  });

  testWidgets('연령대를 바꾸면 다음에 여는 색칠에 적용된다', (tester) async {
    // 계획 3 후속 1.1 의 지뢰가 해체됐는지 본다.
    await tester.pumpWidget(host());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('nav-me')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('age-child')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('nav-play')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('today-tile')));
    await settle(tester);

    expect(find.byType(ToolButton), findsNWidgets(5),
        reason: '새 세션은 새 컨트롤러라 바뀐 설정을 읽는다');
  });

  testWidgets('데이터를 초기화하면 모아보기가 비워진다', (tester) async {
    // 진짜 파일 쓰기는 FakeAsync 아래에서 끝나지 않는다. 실제 존에서 쓴다.
    await tester.runAsync(() => repository.save(Artwork(
          id: 'w1',
          dohanId: 'animal-a',
          fills: const {},
          updatedAt: DateTime.utc(2026, 10, 5),
        )));

    await tester.pumpWidget(host());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);
    expect(find.byType(ArtTile), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-me')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('clear-data')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('clear-confirm')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);

    expect(find.byKey(const ValueKey('gallery-empty')), findsOneWidget);
  });
}
