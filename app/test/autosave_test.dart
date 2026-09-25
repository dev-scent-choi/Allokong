import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/gallery/autosave.dart';

void main() {
  late Directory root;
  late ArtworkRepository repo;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_auto_');
    repo = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Artwork art(int color) => Artwork(
        id: 'a1',
        dohanId: 'flower-01',
        fills: {2: color},
        updatedAt: DateTime.utc(2026, 9, 25),
      );

  test('연달아 예약하면 마지막 것 한 번만 쓴다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(milliseconds: 40),
    );
    addTearDown(auto.dispose);

    auto.schedule(art(0xFF111111));
    auto.schedule(art(0xFF222222));
    auto.schedule(art(0xFF333333));

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(auto.saveCount, 1, reason: '디바운스로 한 번만 써야 한다');
    expect((await repo.load('a1'))!.fills[2], 0xFF333333);
  });

  test('flush 는 기다리지 않고 바로 쓴다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    auto.schedule(art(0xFF444444));
    await auto.flush();

    expect(auto.saveCount, 1);
    expect((await repo.load('a1'))!.fills[2], 0xFF444444);
  });

  test('예약한 것이 없으면 flush 가 아무것도 쓰지 않는다', () async {
    final auto = Autosave(repository: repo);
    addTearDown(auto.dispose);

    await auto.flush();

    expect(auto.saveCount, 0);
  });

  test('dispose 후에는 예약해도 쓰지 않는다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(milliseconds: 20),
    );

    auto.dispose();
    auto.schedule(art(0xFF555555));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(auto.saveCount, 0);
    expect(await repo.load('a1'), isNull);
  });
}
