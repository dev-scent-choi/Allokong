import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_route.dart' show OpenColoring;
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/gallery/gallery_screen.dart';
import 'package:kkumul/ui/art_tile.dart';

/// 진짜 빨강 PNG. 썸네일이 실제로 화면에 올라오는지 보려면 디코딩되는
/// 이미지여야 한다 — 바이트를 손으로 적지 말고 만들어 쓴다.
Uint8List _redPng() {
  final im = img.Image(width: 8, height: 8, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  late Directory root;
  late ArtworkRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_gallery_');
    repository = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> addArtwork(String id, {required DateTime at}) =>
      repository.save(Artwork(
        id: id,
        dohanId: 'flower-01',
        fills: const {2: 0xFFFF0000},
        updatedAt: at,
      ));

  Widget host({int refreshToken = 0, OpenColoring? onOpen}) => MaterialApp(
        home: Scaffold(
          body: GalleryScreen(
            repository: repository,
            refreshToken: refreshToken,
            onOpen: onOpen ??
                ({required String dohanId, required String artworkId}) async {},
          ),
        ),
      );

  /// 썸네일 PNG 디코딩은 엔진 콜백이다. 실제 존에서 한 박자 돌린다.
  Future<void> settle(WidgetTester tester, {Finder? until}) async {
    // 한 번 기다리는 것으로는 모자란다 — 태스크 4 에서 실측했다. 조건이
    // 설 때까지 실제 존에서 기다리며 펌프한다.
    for (var i = 0; i < 100; i++) {
      if (until != null && until.evaluate().isNotEmpty) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 25));
      if (until == null && i >= 19) break; // 조건이 없으면 500ms 로 끝낸다
    }
    await tester.pump(const Duration(milliseconds: 25));
  }

  testWidgets('작품이 없으면 빈 상태 안내를 보여준다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.byKey(const ValueKey('gallery-empty')), findsOneWidget);
    expect(find.byType(ArtTile), findsNothing);
  });

  testWidgets('작품을 최신순으로 보여준다', (tester) async {
    await tester.runAsync(() async {
      await addArtwork('old', at: DateTime.utc(2026, 10, 1));
      await addArtwork('new', at: DateTime.utc(2026, 10, 5));
    });

    await tester.pumpWidget(host());
    await settle(tester);

    final tiles = find.byType(ArtTile);
    expect(tiles, findsNWidgets(2));
    expect(find.byKey(const ValueKey('gallery-empty')), findsNothing);

    final first = tester.widget<ArtTile>(tiles.first);
    expect(first.label, contains('new'), reason: '최근에 고친 것이 먼저다');
  });

  testWidgets('썸네일이 있으면 그것을, 없으면 선화를 보여준다', (tester) async {
    await tester.runAsync(() async {
      await addArtwork('withThumb', at: DateTime.utc(2026, 10, 5));
      await addArtwork('noThumb', at: DateTime.utc(2026, 10, 1));
      await repository.saveThumbnail('withThumb', _redPng());
    });

    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byKey(const ValueKey('thumb-withThumb')), findsOneWidget);
    expect(find.byKey(const ValueKey('lineart-noThumb')), findsOneWidget,
        reason: '강제 종료로 썸네일을 못 구운 경우가 정상 경로에 있다');
  });

  testWidgets('작품을 누르면 그 작품을 이어서 연다', (tester) async {
    await tester.runAsync(
        () => addArtwork('w1', at: DateTime.utc(2026, 10, 5)));
    String? openedArtwork;
    String? openedDohan;

    await tester.pumpWidget(host(
      onOpen: ({required String dohanId, required String artworkId}) async {
        openedDohan = dohanId;
        openedArtwork = artworkId;
      },
    ));
    await settle(tester);

    await tester.tap(find.byType(ArtTile));
    await settle(tester);

    expect(openedArtwork, 'w1', reason: '새 작품이 아니라 그 작품을 이어 그린다');
    expect(openedDohan, 'flower-01');
  });

  testWidgets('refreshToken 이 바뀌면 다시 읽는다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);
    expect(find.byType(ArtTile), findsNothing);

    await tester.runAsync(
        () => addArtwork('w1', at: DateTime.utc(2026, 10, 5)));
    await tester.pumpWidget(host(refreshToken: 1));
    await settle(tester, until: find.byType(ArtTile));

    expect(find.byType(ArtTile), findsOneWidget,
        reason: '색칠에서 돌아왔는데 새 작품이 안 보이면 안 된다');
  });
}
