import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/settings/settings.dart';
import 'package:kkumul/settings/settings_screen.dart';

void main() {
  late Directory root;
  late ArtworkRepository repository;
  late SettingsStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_settings_');
    repository = ArtworkRepository(root);
    store = SettingsStore(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Widget host({
    AgeMode ageMode = AgeMode.toddler,
    ValueChanged<AgeMode>? onChanged,
    VoidCallback? onCleared,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            store: store,
            repository: repository,
            ageMode: ageMode,
            onAgeModeChanged: onChanged ?? (_) {},
            onDataCleared: onCleared,
          ),
        ),
      );

  /// 버튼을 누른 뒤 **진짜 파일 쓰기**가 끝나기를 기다린다.
  ///
  /// `pumpAndSettle` 은 애니메이션만 끝내 준다. `SettingsStore.save` 와
  /// `ArtworkRepository.deleteAll` 은 진짜 파일 I/O 라 FakeAsync 아래에서는
  /// 완료되지 않는다 — 실제 존에서 돌려 줘야 한다.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  testWidgets('연령대를 고르면 알려주고 저장한다', (tester) async {
    AgeMode? picked;
    await tester.pumpWidget(host(onChanged: (m) => picked = m));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('age-child')));
    await settle(tester);

    expect(picked, AgeMode.child);
    expect(
      (await tester.runAsync(() => store.load()))!.ageMode,
      AgeMode.child,
    );
  });

  testWidgets('데이터 초기화는 두 단계를 거친다', (tester) async {
    await tester.runAsync(() => repository.save(Artwork(
      id: 'w1',
      dohanId: 'flower-01',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 6),
    )));

    await tester.pumpWidget(host());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('clear-data')));
    await settle(tester);

    // 1단계: 아직 아무것도 지워지지 않았다
    expect(await tester.runAsync(() => repository.listAll()), hasLength(1));
    expect(find.byKey(const ValueKey('clear-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-confirm')));
    await settle(tester);

    expect(await tester.runAsync(() => repository.listAll()), isEmpty);
  });

  testWidgets('확인에서 취소하면 아무것도 지워지지 않는다', (tester) async {
    await tester.runAsync(() => repository.save(Artwork(
      id: 'w1',
      dohanId: 'flower-01',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 6),
    )));

    await tester.pumpWidget(host());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('clear-data')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('clear-cancel')));
    await settle(tester);

    expect(await tester.runAsync(() => repository.listAll()), hasLength(1));
    expect(find.byKey(const ValueKey('clear-confirm')), findsNothing);
  });

  testWidgets('지운 뒤 셸에 알려준다', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(host(onCleared: () => cleared++));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('clear-data')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('clear-confirm')));
    await settle(tester);

    expect(cleared, 1, reason: '모아보기가 빈 것을 알아야 한다');
  });

  testWidgets('연령대 버튼도 64dp 를 지킨다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await settle(tester);

    for (final key in ['age-toddler', 'age-child']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.height, greaterThanOrEqualTo(64));
    }
  });
}
