import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/coloring_controller.dart' show ToolKind;
import 'package:kkumul/coloring/sticker_state.dart';
import 'package:kkumul/ui/palette_shades.dart';
import 'package:kkumul/ui/shade_button.dart';
import 'package:kkumul/ui/sticker_drawer.dart';
import 'package:kkumul/ui/tool_bar.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('도구가 다섯 개이고 전부 64dp 이상이다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      ToolBar(selected: ToolKind.bucket, onSelect: (_) {}),
    ));

    final tools = find.byType(ToolButton);
    expect(tools, findsNWidgets(5));

    for (final e in tools.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.right, lessThanOrEqualTo(320),
          reason: '다섯 개가 320dp 한 줄에 정확히 들어가야 한다');
    }
  });

  testWidgets('도구를 누르면 알려준다', (tester) async {
    ToolKind? picked;
    await tester.pumpWidget(_host(
      ToolBar(selected: ToolKind.bucket, onSelect: (t) => picked = t),
    ));

    await tester.tap(find.byType(ToolButton).at(3));
    expect(picked, ToolKind.eraser, reason: '네 번째가 지우개다');
  });

  testWidgets('고른 도구만 선택 표시가 켜진다', (tester) async {
    await tester.pumpWidget(_host(
      ToolBar(selected: ToolKind.brush, onSelect: (_) {}),
    ));

    final tools = find.byType(ToolButton);
    for (var i = 0; i < 5; i++) {
      expect(tester.widget<ToolButton>(tools.at(i)).selected, i == 2,
          reason: '$i 번째');
    }
  });

  testWidgets('명도 버튼이 64dp 이고 누르면 알려준다', (tester) async {
    var cycled = 0;
    await tester.pumpWidget(_host(
      ShadeButton(shade: Shade.base, onCycle: () => cycled++),
    ));

    final size = tester.getSize(find.byType(ShadeButton));
    expect(size.width, greaterThanOrEqualTo(64));
    expect(size.height, greaterThanOrEqualTo(64));

    await tester.tap(find.byType(ShadeButton));
    expect(cycled, 1);
  });

  testWidgets('스티커 서랍이 열 개를 보여주고 64dp 를 지킨다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(StickerDrawer(onPick: (_) {})));
    await tester.pumpAndSettle();

    final items = find.byType(StickerButton);
    expect(items, findsNWidgets(kStickerIds.length));

    for (final e in items.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.right, lessThanOrEqualTo(320));
    }
  });

  testWidgets('스티커를 누르면 id 를 알려준다', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(StickerDrawer(onPick: (id) => picked = id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(StickerButton).first);
    expect(picked, kStickerIds.first);
  });
}
