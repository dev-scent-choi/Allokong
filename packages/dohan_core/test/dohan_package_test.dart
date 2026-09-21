import 'dart:io';

import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('dohan_pkg_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('computeRegionCentroids', () {
    test('영역별 중심 좌표를 계산한다', () {
      final map = RegionMap.filled(6, 2, kRegionBackground);
      map.set(0, 0, 2);
      map.set(2, 0, 2);
      map.set(4, 1, 3);

      final centroids = computeRegionCentroids(map);

      expect(centroids[2], [1, 0]);
      expect(centroids[3], [4, 1]);
      expect(centroids.containsKey(kRegionBackground), isFalse);
    });
  });

  group('DohanMeta', () {
    test('JSON 왕복이 값을 보존한다', () {
      final meta = DohanMeta(
        id: 'dino-tri-01',
        title: '삼각 공룡',
        category: 'dinosaur',
        source: 'bundled',
        canvasSize: [1024, 1024],
        regionCount: 23,
        difficulty: 2,
        suggestedPalette: ['#63b98b', '#f1bd45'],
        regionCentroids: {2: [412, 330]},
        createdAt: DateTime.utc(2026, 9, 21),
      );

      final restored = DohanMeta.fromJson(meta.toJson());

      expect(restored.id, meta.id);
      expect(restored.title, meta.title);
      expect(restored.category, meta.category);
      expect(restored.canvasSize, meta.canvasSize);
      expect(restored.regionCount, 23);
      expect(restored.suggestedPalette, ['#63b98b', '#f1bd45']);
      expect(restored.regionCentroids[2], [412, 330]);
      expect(restored.createdAt, meta.createdAt);
    });
  });

  group('도안 패키지 입출력', () {
    test('세 파일을 쓰고 그대로 읽는다', () async {
      final lineart = img.Image(width: 8, height: 8, numChannels: 4);
      img.fill(lineart, color: img.ColorRgba8(0, 0, 0, 0));
      final regions = RegionMap.filled(8, 8, kRegionBackground);
      regions.set(3, 3, 2);
      regions.set(4, 3, 2);
      final meta = DohanMeta(
        id: 'test-01',
        title: '테스트 도안',
        category: 'animal',
        source: 'bundled',
        canvasSize: [8, 8],
        regionCount: 1,
        difficulty: 1,
        suggestedPalette: ['#ef7586'],
        regionCentroids: computeRegionCentroids(regions),
        createdAt: DateTime.utc(2026, 9, 21),
      );

      await writeDohanPackage(
        dir: tmp,
        lineart: lineart,
        regions: regions,
        meta: meta,
      );

      expect(File('${tmp.path}/lineart.png').existsSync(), isTrue);
      expect(File('${tmp.path}/regions.png').existsSync(), isTrue);
      expect(File('${tmp.path}/meta.json').existsSync(), isTrue);

      final pkg = await readDohanPackage(tmp);

      expect(pkg.meta.id, 'test-01');
      expect(pkg.meta.title, '테스트 도안');
      expect(pkg.regions.at(3, 3), 2);
      expect(pkg.regions.at(0, 0), kRegionBackground);
      expect(pkg.lineart.width, 8);
    });

    test('meta.json은 사람이 읽을 수 있게 들여쓰기된다', () async {
      final lineart = img.Image(width: 2, height: 2, numChannels: 4);
      final regions = RegionMap.filled(2, 2, kRegionBackground);
      await writeDohanPackage(
        dir: tmp,
        lineart: lineart,
        regions: regions,
        meta: DohanMeta(
          id: 'x',
          title: 'x',
          category: 'animal',
          source: 'bundled',
          canvasSize: [2, 2],
          regionCount: 0,
          difficulty: 1,
          suggestedPalette: const [],
          regionCentroids: const {},
          createdAt: DateTime.utc(2026, 9, 21),
        ),
      );

      final text = File('${tmp.path}/meta.json').readAsStringSync();

      expect(text, contains('\n  "id"'));
    });
  });
}
