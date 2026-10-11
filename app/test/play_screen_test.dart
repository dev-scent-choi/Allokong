import 'dart:io';
import 'dart:typed_data';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_route.dart' show OpenColoring;
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/play/play_screen.dart';
import 'package:kkumul/ui/art_tile.dart';

/// 카테고리 넷에 셋씩, 실제 라이브러리와 같은 모양의 가짜 소스.
///
/// `load` 는 부르지 않는다 — 놀기는 `loadMeta` 만 쓴다. 불리면 테스트가
/// 실패하도록 던져 둔다.
class FakeLibrary implements DohanSource {
  static const _ids = [
    'animal-a', 'animal-b', 'animal-c', //
    'car-a', 'car-b', 'car-c',
    'dino-a', 'dino-b', 'dino-c',
    'shape-a', 'shape-b', 'shape-c',
  ];

  @override
  Future<List<String>> listIds() async => _ids;

  @override
  Future<DohanPackage> load(String id) async =>
      throw StateError('놀기가 도안 전체를 읽으면 안 된다: $id');

  @override
  Future<DohanMeta> loadMeta(String id) async => DohanMeta(
        id: id,
        title: '제목 $id',
        category: id.split('-').first == 'dino'
            ? 'dinosaur'
            : id.split('-').first,
        source: 'bundled',
        canvasSize: const [1024, 1024],
        regionCount: 4,
        difficulty: 1,
        suggestedPalette: const [],
        regionAnchors: const {},
        createdAt: DateTime.utc(2026, 10, 6),
      );
}

Uint8List _redPng() {
  final im = img.Image(width: 8, height: 8, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  late Directory root;
  late ArtworkRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_play_');
    repository = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Widget host({
    OpenColoring? onOpen,
    DateTime? today,
    int refreshToken = 0,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: PlayScreen(
            source: FakeLibrary(),
            repository: repository,
            today: today,
            refreshToken: refreshToken,
            onOpen: onOpen ??
                ({required String dohanId, required String artworkId}) async {},
          ),
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

  testWidgets('카테고리 넷을 제목과 함께 세로로 펼친다', (tester) async {
    // 목록은 게으르게 짓는다 — 네 카테고리가 다 보이도록 화면을 길게 늘인다.
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await settle(tester);

    for (final name in ['동물', '자동차', '공룡', '모양']) {
      expect(find.text(name), findsOneWidget, reason: '$name 제목이 없다');
    }

    expect(find.byType(Scrollable), findsWidgets);
    // 가로로 밀리는 줄이 하나도 없어야 한다. 글을 못 읽는 아이에게
    // 가로 스크롤은 "없는 것"이다.
    for (final e in find.byType(Scrollable).evaluate()) {
      final s = e.widget as Scrollable;
      expect(s.axisDirection, isNot(AxisDirection.right));
      expect(s.axisDirection, isNot(AxisDirection.left));
    }
  });

  testWidgets('오늘의 도안은 하루 동안 같고 날이 바뀌면 바뀐다', (tester) async {
    final todayTile = find.byKey(const ValueKey('today-tile'));
    String label() => tester.widget<ArtTile>(todayTile).label;

    // 지역 새벽 2시는 UTC 로는 전날이다. 지역 날짜로 세야 같은 날이다.
    await tester.pumpWidget(host(today: DateTime(2026, 10, 6, 2)));
    await settle(tester, todayTile);
    final first = label();

    await tester.pumpWidget(host(today: DateTime(2026, 10, 6, 23)));
    await tester.pump();
    expect(label(), first, reason: '같은 날에는 같은 도안이어야 한다');

    await tester.pumpWidget(host(today: DateTime(2026, 10, 7, 2)));
    await tester.pump();
    expect(label(), isNot(first), reason: '내일은 달라야 한다');
  });

  testWidgets('320x640 에서도 넘치지 않고 카테고리에 닿을 수 있다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 이어 그리기까지 있는 가장 긴 경우로 잰다.
    await tester.runAsync(() => repository.save(Artwork(
          id: 'w1',
          dohanId: 'animal-a',
          fills: const {},
          updatedAt: DateTime.utc(2026, 10, 5),
        )));
    await tester.pumpWidget(host());
    await settle(tester, find.byKey(const ValueKey('continue-tile')));
    expect(tester.takeException(), isNull);

    // 첫 화면에 동물 카테고리가 들어와야 한다.
    expect(find.text('동물'), findsOneWidget);
    expect(tester.getTopLeft(find.text('동물')).dy, lessThan(640),
        reason: '동물 제목이 첫 화면 밖에 있다');

    for (final e in find.byType(ArtTile).evaluate()) {
      final size = e.size!;
      expect(size.width, greaterThanOrEqualTo(64));
      expect(size.height, greaterThanOrEqualTo(64));
    }

    await tester.scrollUntilVisible(find.text('모양'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('모양'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('도안을 누르면 새 작품으로 연다', (tester) async {
    String? openedDohan;
    String? openedArtwork;

    await tester.pumpWidget(host(
      onOpen: ({required String dohanId, required String artworkId}) async {
        openedDohan = dohanId;
        openedArtwork = artworkId;
      },
    ));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('today-tile')));
    await settle(tester);

    expect(openedDohan, isNotNull);
    expect(openedArtwork, startsWith('$openedDohan-'),
        reason: '놀기는 언제나 새 작품으로 시작한다');
  });

  testWidgets('작품이 없으면 이어 그리기 칸을 통째로 뺀다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.byKey(const ValueKey('continue-tile')), findsNothing);
  });

  testWidgets('이어 그리기는 가장 최근 작품을 그대로 연다', (tester) async {
    await tester.runAsync(() => repository.save(Artwork(
      id: 'old',
      dohanId: 'animal-a',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 1),
    )));
    await tester.runAsync(() => repository.save(Artwork(
      id: 'recent',
      dohanId: 'car-b',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 5),
    )));
    String? openedArtwork;

    await tester.pumpWidget(host(
      onOpen: ({required String dohanId, required String artworkId}) async {
        openedArtwork = artworkId;
      },
    ));
    await settle(tester);

    expect(find.byKey(const ValueKey('continue-tile')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('continue-tile')));
    await settle(tester);

    expect(openedArtwork, 'recent', reason: '새 작품이 아니라 그 작품을 잇는다');
  });

  testWidgets('refreshToken 이 바뀌면 이어 그리기를 다시 읽는다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);
    expect(find.byKey(const ValueKey('continue-tile')), findsNothing);

    await tester.runAsync(() => repository.save(Artwork(
      id: 'w1',
      dohanId: 'animal-a',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 5),
    )));
    await tester.pumpWidget(host(refreshToken: 1));
    await settle(tester);

    expect(find.byKey(const ValueKey('continue-tile')), findsOneWidget);
  });

  testWidgets('이어 그리기 칸은 썸네일이 있으면 그 그림을 보여준다', (tester) async {
    await tester.runAsync(() async {
      await repository.save(Artwork(
        id: 'w1',
        dohanId: 'animal-a',
        fills: const {},
        updatedAt: DateTime.utc(2026, 10, 5),
      ));
      await repository.saveThumbnail('w1', _redPng());
    });

    await tester.pumpWidget(host());
    await settle(tester, find.byKey(const ValueKey('continue-thumb')));

    expect(find.byKey(const ValueKey('continue-thumb')), findsOneWidget,
        reason: '아이가 칠한 그림이어야 한다');
  });

  testWidgets('이어 그리기 칸은 썸네일이 없으면 선화로 떨어진다', (tester) async {
    await tester.runAsync(() => repository.save(Artwork(
          id: 'w1',
          dohanId: 'animal-a',
          fills: const {},
          updatedAt: DateTime.utc(2026, 10, 5),
        )));

    await tester.pumpWidget(host());
    await settle(tester, find.byKey(const ValueKey('continue-tile')));

    expect(find.byKey(const ValueKey('continue-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('continue-thumb')), findsNothing);
  });

  testWidgets('선화는 칸 크기로 줄여 디코딩한다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    final img = tester.widget<Image>(find.byType(Image).first);
    expect(img.image, isA<ResizeImage>());
    expect((img.image as ResizeImage).width, 288,
        reason: '144dp 칸에 1024 제곱을 통째로 디코딩하면 안 된다');
  });
}
