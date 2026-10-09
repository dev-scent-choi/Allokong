import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/ui/art_tile.dart';

void main() {
  testWidgets('정사각형이고 좁은 화면에서도 64dp 를 지킨다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 0; i < 4; i++)
              ArtTile(
                label: '칸 $i',
                onTap: () {},
                child: const ColoredBox(color: Colors.amber),
              ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    for (final e in find.byType(ArtTile).evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(kArtTileMinSize));
      expect(r.height, greaterThanOrEqualTo(kArtTileMinSize));
      expect(r.width, closeTo(r.height, 1.0), reason: '정사각이어야 한다');
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320),
          reason: '화면 밖으로 밀려난 칸은 아이에게 없는 칸이다');
    }
  });

  testWidgets('누르면 알려준다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 144,
            height: 144,
            child: ArtTile(
              label: '고양이',
              onTap: () => taps++,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(ArtTile));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('그림이 비어 있어도 누를 수 있다', (tester) async {
    // 썸네일이 아직 안 읽혔을 때다. 투명한 칸이 입력을 흘려보내면
    // 아이는 "눌리지 않는 그림"을 만난다.
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 144,
            height: 144,
            child: ArtTile(
              label: '빈 칸',
              onTap: () => taps++,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));

    await tester.tapAt(tester.getCenter(find.byType(ArtTile)));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('읽어 줄 이름을 단다', (tester) async {
    // 글을 못 읽는 아이를 위한 것이 아니라, 접근성 도구와 테스트가
    // 칸을 구분할 수 있게 하는 것이다.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 144,
            height: 144,
            child: ArtTile(
              label: '고양이',
              onTap: () {},
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));

    expect(find.bySemanticsLabel('고양이'), findsOneWidget);
  });
}
