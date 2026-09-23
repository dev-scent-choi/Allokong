import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dohan_core/dohan_core.dart';
import 'package:dohan_core/dohan_core_io.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('dohan_pkg_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('computeRegionAnchors', () {
    test('앵커는 언제나 자기 영역 안에 있다', () {
      final map = RegionMap.filled(6, 2, kRegionBackground);
      map.set(0, 0, 2);
      map.set(2, 0, 2);
      map.set(4, 1, 3);

      final anchors = computeRegionAnchors(map);

      for (final entry in anchors.entries) {
        final id = entry.key;
        final xy = entry.value;
        expect(map.at(xy[0], xy[1]), id,
            reason: '영역 $id 의 앵커 $xy 가 자기 영역 밖이다');
      }
      expect(anchors.keys.toSet(), {2, 3});
      expect(anchors.containsKey(kRegionBackground), isFalse);
    });

    test('고리 모양에서도 앵커가 구멍이 아니라 고리 위에 있다', () {
      // 가운데가 뚫린 5x5 고리. 무게중심은 정확히 구멍 한가운데로 떨어진다.
      final map = RegionMap.filled(5, 5, kRegionLine);
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final onRing = x == 0 || y == 0 || x == 4 || y == 4;
          map.set(x, y, onRing ? 2 : kRegionLine);
        }
      }

      final anchor = computeRegionAnchors(map)[2]!;

      expect(map.at(anchor[0], anchor[1]), 2,
          reason: '앵커가 고리 위에 있어야 한다');
      expect(anchor, isNot([2, 2]), reason: '무게중심은 구멍 한가운데다');
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
        regionAnchors: {2: [412, 330]},
        createdAt: DateTime.utc(2026, 9, 21),
      );

      final restored = DohanMeta.fromJson(meta.toJson());

      expect(restored.id, meta.id);
      expect(restored.title, meta.title);
      expect(restored.category, meta.category);
      expect(restored.canvasSize, meta.canvasSize);
      expect(restored.regionCount, 23);
      expect(restored.suggestedPalette, ['#63b98b', '#f1bd45']);
      expect(restored.regionAnchors[2], [412, 330]);
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
        regionAnchors: computeRegionAnchors(regions),
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
          regionAnchors: const {},
          createdAt: DateTime.utc(2026, 9, 21),
        ),
      );

      final text = File('${tmp.path}/meta.json').readAsStringSync();

      expect(text, contains('\n  "id"'));
    });
  });

  group('DohanPackage.fromBytes', () {
    test('디스크를 거치지 않고 바이트에서 도안을 만든다', () async {
      // Flutter 에셋으로 실린 내장 도안은 File 이 아니라 바이트로 온다.
      final lineart = img.Image(width: 8, height: 8, numChannels: 4);
      final regions = RegionMap.filled(8, 8, kRegionBackground);
      regions.set(3, 3, 2);
      final meta = DohanMeta(
        id: 'asset-01',
        title: '에셋 도안',
        category: 'animal',
        source: 'bundled',
        canvasSize: [8, 8],
        regionCount: 1,
        difficulty: 1,
        suggestedPalette: const ['#ef7586'],
        regionAnchors: computeRegionAnchors(regions),
        createdAt: DateTime.utc(2026, 9, 23),
      );

      final pkg = DohanPackage.fromBytes(
        metaJson: jsonEncode(meta.toJson()),
        lineartPng: Uint8List.fromList(img.encodePng(lineart)),
        regionsPng: encodeIndexMapPng(regions),
        label: 'assets/dohans/asset-01',
      );

      expect(pkg.meta.id, 'asset-01');
      expect(pkg.regions.at(3, 3), 2);
      expect(pkg.lineart.width, 8);
    });

    test('메타가 깨지면 넘긴 이름을 지목한다', () {
      expect(
        () => DohanPackage.fromBytes(
          metaJson: '{ 이건 JSON이 아니다',
          lineartPng: Uint8List(0),
          regionsPng: Uint8List(0),
          label: 'assets/dohans/bad',
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('assets/dohans/bad'), contains('해석할 수 없습니다')),
        )),
      );
    });
  });

  group('읽기 실패', () {
    test('파일이 없으면 어느 파일인지 한국어로 알려준다', () async {
      await expectLater(
        readDohanPackage(tmp),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('meta.json'), contains('열 수 없습니다')),
        )),
      );
    });

    test('meta.json 이 깨졌으면 해석 실패를 한국어로 알려준다', () async {
      File('${tmp.path}/meta.json').writeAsStringSync('{ 이건 JSON이 아니다');

      await expectLater(
        readDohanPackage(tmp),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('해석할 수 없습니다'),
        )),
      );
    });

    test('lineart.png 가 없으면 그 파일을 지목한다', () async {
      File('${tmp.path}/meta.json').writeAsStringSync(
        '{"id":"x","title":"x","category":"animal","source":"bundled",'
        '"canvasSize":[2,2],"regionCount":0,"difficulty":1,'
        '"suggestedPalette":[],"regionAnchors":{},'
        '"createdAt":"2026-09-21T00:00:00.000Z"}',
      );

      await expectLater(
        readDohanPackage(tmp),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('lineart.png'),
        )),
      );
    });
  });
}
