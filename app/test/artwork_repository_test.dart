import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/sticker_state.dart';
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/gallery/artwork_repository.dart';

void main() {
  late Directory root;
  late ArtworkRepository repo;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_art_');
    repo = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Artwork sample({String id = 'a1', Map<int, int>? fills}) => Artwork(
        id: id,
        dohanId: 'flower-01',
        fills: fills ?? {2: 0xFFEF7586, 300: 0xFF6CAEE0},
        updatedAt: DateTime.utc(2026, 9, 25, 12),
      );

  test('저장한 작품을 그대로 읽는다', () async {
    await repo.save(sample());

    final loaded = await repo.load('a1');

    expect(loaded, isNotNull);
    expect(loaded!.dohanId, 'flower-01');
    expect(loaded.fills[2], 0xFFEF7586);
    expect(loaded.fills[300], 0xFF6CAEE0);
    expect(loaded.updatedAt, DateTime.utc(2026, 9, 25, 12));
  });

  test('없는 작품은 null 이다', () async {
    expect(await repo.load('없음'), isNull);
  });

  test('작품마다 폴더가 하나씩 생긴다', () async {
    await repo.save(sample(id: 'a1'));
    await repo.save(sample(id: 'a2'));

    expect(Directory('${root.path}/artworks/a1').existsSync(), isTrue);
    expect(File('${root.path}/artworks/a1/artwork.json').existsSync(), isTrue);
    expect(Directory('${root.path}/artworks/a2').existsSync(), isTrue);
  });

  test('목록은 디렉터리를 훑어 만들고 최근 순으로 준다', () async {
    await repo.save(Artwork(
        id: 'old',
        dohanId: 'flower-01',
        fills: const {},
        updatedAt: DateTime.utc(2026, 1, 1)));
    await repo.save(Artwork(
        id: 'new',
        dohanId: 'flower-01',
        fills: const {},
        updatedAt: DateTime.utc(2026, 9, 1)));

    final all = await repo.listAll();

    expect(all.map((a) => a.id), ['new', 'old']);
  });

  test('폴더 하나가 깨져도 나머지는 읽힌다', () async {
    await repo.save(sample(id: 'good'));
    final bad = Directory('${root.path}/artworks/bad')..createSync();
    File('${bad.path}/artwork.json').writeAsStringSync('{ 망가진 JSON');

    final all = await repo.listAll();

    expect(all.map((a) => a.id), ['good'],
        reason: '중앙 인덱스가 없으니 손상은 그 폴더에만 갇힌다');
  });

  test('덮어쓰기는 임시 파일을 거친다', () async {
    await repo.save(sample(fills: {2: 0xFFEF7586}));
    await repo.save(sample(fills: {2: 0xFF63B98B}));

    final loaded = await repo.load('a1');

    expect(loaded!.fills[2], 0xFF63B98B);
    expect(File('${root.path}/artworks/a1/artwork.json.tmp').existsSync(),
        isFalse,
        reason: '임시 파일이 남으면 안 된다');
  });

  test('삭제하면 폴더가 사라진다', () async {
    await repo.save(sample());

    await repo.delete('a1');

    expect(await repo.load('a1'), isNull);
    expect(Directory('${root.path}/artworks/a1').existsSync(), isFalse);
  });

  test('읽기 자체가 실패하면 null 로 뭉개지 않고 던진다', () async {
    // artwork.json 자리에 디렉터리를 만들어 읽기를 실패시킨다.
    // 권한 오류나 파일 잠김과 같은 부류다.
    Directory('${root.path}/artworks/locked/artwork.json')
        .createSync(recursive: true);

    await expectLater(
      repo.load('locked'),
      throwsA(isA<FileSystemException>()),
      reason: 'null 을 돌려주면 호출자가 새로 시작해 멀쩡한 파일을 덮어쓴다',
    );
  });

  test('listAll 은 읽을 수 없는 폴더를 건너뛴다', () async {
    await repo.save(sample(id: 'good'));
    Directory('${root.path}/artworks/locked/artwork.json')
        .createSync(recursive: true);

    final all = await repo.listAll();

    expect(all.map((a) => a.id), ['good'],
        reason: '한 폴더를 못 읽어도 목록은 나머지를 보여준다');
  });

  test('스티커를 따로 저장하고 읽는다', () async {
    await repo.save(
      sample(),
      stickers: [
        Sticker(instanceId: 'a', stickerId: 'star-01', x: 10, y: 20),
      ],
    );

    final back = await repo.loadStickers('a1');
    expect(back, hasLength(1));
    expect(back.first.stickerId, 'star-01');
    expect(back.first.x, 10);
  });

  test('스티커가 없으면 파일도 없고 빈 목록을 준다', () async {
    await repo.save(sample());
    expect(await repo.loadStickers('a1'), isEmpty);
    expect(File('${root.path}/artworks/a1/stickers.json').existsSync(), isFalse);
  });

  test('브러시 PNG 를 주면 쓰고 안 주면 건드리지 않는다', () async {
    final png = Uint8List.fromList([1, 2, 3, 4]);
    await repo.save(sample(), brushPng: png);
    expect(await repo.loadBrushPng('a1'), png);

    // 두 번째 저장은 브러시를 안 준다 — 기존 파일이 그대로 있어야 한다.
    await repo.save(sample());
    expect(await repo.loadBrushPng('a1'), png,
        reason: 'null 은 "지워라"가 아니라 "건드리지 마라"다');
  });

  test('브러시가 없으면 null 이다', () async {
    await repo.save(sample());
    expect(await repo.loadBrushPng('a1'), isNull);
  });

  test('스티커가 깨져도 채움과 브러시는 살아난다', () async {
    await repo.save(
      sample(),
      stickers: [Sticker(instanceId: 'a', stickerId: 'star-01', x: 1, y: 2)],
      brushPng: Uint8List.fromList([9, 9]),
    );
    // stickers.json 만 망가뜨린다
    File('${root.path}/artworks/a1/stickers.json').writeAsStringSync('[[[');

    expect(await repo.load('a1'), isNotNull, reason: '채움은 멀쩡해야 한다');
    expect(await repo.loadStickers('a1'), isEmpty, reason: '깨진 스티커는 버린다');
    expect(await repo.loadBrushPng('a1'), isNotNull);
  });
}
