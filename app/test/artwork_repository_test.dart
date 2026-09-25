import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
