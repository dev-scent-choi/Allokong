import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/ui/palette_bar.dart';
import 'package:kkumul/ui/palette_shades.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Column(children: [const Spacer(), child])),
    );

void main() {
  testWidgets('고른 명도의 여덟 색을 보여준다', (tester) async {
    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.dark,
      selectedIndex: 0,
      onPickIndex: (_) {},
    )));

    final swatches = find.byType(ColorSwatchButton);
    expect(swatches, findsNWidgets(8));

    final first = tester.widget<ColorSwatchButton>(swatches.first);
    expect(first.color, paletteShades[Shade.dark]!.first);
  });

  testWidgets('색을 누르면 인덱스를 준다', (tester) async {
    int? picked;
    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.base,
      selectedIndex: 0,
      onPickIndex: (i) => picked = i,
    )));

    await tester.tap(find.byType(ColorSwatchButton).at(4));
    expect(picked, 4,
        reason: '색이 아니라 자리를 준다 — 명도가 바뀌어도 자리는 유지된다');
  });

  testWidgets('좁은 화면에서도 여덟 색이 전부 화면 안에 있고 64dp 를 지킨다',
      (tester) async {
    // 계획 2 는 위젯 테스트가 전부 800x600 에서 돌아, 여덟 색 중 둘이 화면
    // 밖으로 밀린 것을 태스크 리뷰 열 번이 놓쳤다. 이번에는 1번 태스크부터 본다.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.base,
      selectedIndex: 3,
      onPickIndex: (_) {},
    )));

    final swatches = find.byType(ColorSwatchButton);
    expect(swatches, findsNWidgets(8));

    for (final e in swatches.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320),
          reason: '화면 밖으로 밀려난 색은 아이에게 없는 색이다');
    }
  });

  testWidgets('고른 자리만 선택 표시가 켜진다', (tester) async {
    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.base,
      selectedIndex: 6,
      onPickIndex: (_) {},
    )));

    final swatches = find.byType(ColorSwatchButton);
    for (var i = 0; i < 8; i++) {
      expect(tester.widget<ColorSwatchButton>(swatches.at(i)).selected, i == 6,
          reason: '$i 번째');
    }
  });

  testWidgets('명도를 바꿔도 고른 자리는 그대로다', (tester) async {
    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.light,
      selectedIndex: 6,
      onPickIndex: (_) {},
    )));

    final swatches = find.byType(ColorSwatchButton);
    expect(tester.widget<ColorSwatchButton>(swatches.at(6)).selected, isTrue);
    expect(tester.widget<ColorSwatchButton>(swatches.at(6)).color,
        paletteShades[Shade.light]![6]);
  });
}
