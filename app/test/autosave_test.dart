import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/sticker_state.dart';
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
    addTearDown(auto.dispose);

    auto.dispose();
    auto.schedule(art(0xFF555555));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(auto.saveCount, 0);
    expect(await repo.load('a1'), isNull);
  });

  test('저장이 겹쳐도 죽지 않고 마지막 것이 남는다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    auto.schedule(art(0xFF111111));
    final first = auto.flush();
    auto.schedule(art(0xFF222222));
    final second = auto.flush();
    await Future.wait([first, second]);

    expect((await repo.load('a1'))!.fills[2], 0xFF222222);
  });

  test('저장이 실패해도 던지지 않고 다음 저장에서 다시 쓴다', () async {
    final flaky = _FlakyRepository(root);
    final auto = Autosave(
      repository: flaky,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    flaky.failNext = true;
    auto.schedule(art(0xFF666666));
    await auto.flush();

    expect(auto.saveCount, 0, reason: '실패했으니 쓴 것으로 세면 안 된다');
    expect(await repo.load('a1'), isNull);

    flaky.failNext = false;
    await auto.flush();

    expect(auto.saveCount, 1);
    expect((await repo.load('a1'))!.fills[2], 0xFF666666);
  });

  test('브러시가 바뀌지 않으면 굽지 않는다', () async {
    // 굽는 데 53ms 가 든다. 채움만 바꾸는 아이는 이 비용을 내면 안 된다.
    var baked = 0;
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    Future<Uint8List?> bake() async {
      baked++;
      return Uint8List.fromList([1]);
    }

    auto.schedule(art(0xFF111111), brushRevision: 7, bakeBrush: bake);
    await auto.flush();
    expect(baked, 1, reason: '처음에는 한 번 굽는다');

    auto.schedule(art(0xFF222222), brushRevision: 7, bakeBrush: bake);
    await auto.flush();
    expect(baked, 1, reason: '개정 번호가 같으면 다시 굽지 않는다');

    auto.schedule(art(0xFF333333), brushRevision: 8, bakeBrush: bake);
    await auto.flush();
    expect(baked, 2, reason: '바뀌었으면 굽는다');
  });

  test('굽는 함수를 안 주면 부르지 않는다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    auto.schedule(art(0xFF444444));
    await auto.flush();

    expect(auto.saveCount, 1);
    expect(await repo.loadBrushPng('a1'), isNull);
  });

  test('스티커도 함께 쓴다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    auto.schedule(
      art(0xFF555555),
      stickers: [Sticker(instanceId: 'a', stickerId: 'star-01', x: 5, y: 6)],
    );
    await auto.flush();

    expect(await repo.loadStickers('a1'), hasLength(1));
  });
}

/// 한 번만 실패하게 만들 수 있는 저장소. 디스크가 꽉 찼거나 잠긴 상황을
/// 흉내 낸다.
class _FlakyRepository extends ArtworkRepository {
  _FlakyRepository(super.root);

  bool failNext = false;

  @override
  Future<void> save(
    Artwork artwork, {
    List<Sticker> stickers = const [],
    Uint8List? brushPng,
  }) async {
    if (failNext) throw const FileSystemException('테스트용 저장 실패');
    return super.save(artwork, stickers: stickers, brushPng: brushPng);
  }
}
