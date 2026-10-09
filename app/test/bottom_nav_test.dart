import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/shell/bottom_nav.dart';

void main() {
  Widget host({
    ShellTab selected = ShellTab.play,
    ValueChanged<ShellTab>? onSelect,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar:
              BottomNav(selected: selected, onSelect: onSelect ?? (_) {}),
        ),
      );

  testWidgets('좁은 화면에서 다섯 칸이 64dp 를 지키고 제스처 영역을 피한다',
      (tester) async {
    // 다섯 칸 x 64dp = 정확히 320dp. 여유가 0 이라 한 픽셀만 어긋나도
    // 칸이 화면 밖으로 밀리거나 터치 타겟이 깎인다.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final slots = find.byType(NavSlot);
    expect(slots, findsNWidgets(5));

    for (final e in slots.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320),
          reason: '화면 밖으로 밀려난 칸은 아이에게 없는 칸이다');
      expect(r.bottom, lessThanOrEqualTo(640 - 34),
          reason: '제스처 영역에 걸치면 탭 대신 홈 제스처가 먹는다');
    }
  });

  testWidgets('아이콘과 한글 라벨을 함께 보여준다', (tester) async {
    // 상위 스펙 10.1 — 색만으로 의미를 전달하지 않는다.
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    for (final label in ['놀기', '모아보기', '만들기', '랭크', '내 정보']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(Icon), findsNWidgets(5));
  });

  testWidgets('칸을 누르면 알려준다', (tester) async {
    final picked = <ShellTab>[];
    await tester.pumpWidget(host(onSelect: picked.add));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await tester.tap(find.byKey(const ValueKey('nav-me')));
    await tester.pump();

    expect(picked, [ShellTab.gallery, ShellTab.me]);
  });

  testWidgets('고른 칸이 색만이 아니라 모양으로도 구분된다', (tester) async {
    await tester.pumpWidget(host(selected: ShellTab.gallery));
    await tester.pumpAndSettle();

    final slots = tester
        .widgetList<NavSlot>(find.byType(NavSlot))
        .toList();
    expect(slots.where((s) => s.selected), hasLength(1));
    expect(slots.firstWhere((s) => s.selected).tab, ShellTab.gallery);
  });
}
