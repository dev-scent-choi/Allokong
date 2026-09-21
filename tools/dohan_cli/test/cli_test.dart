import 'dart:io';

import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import '../bin/dohan.dart' as cli;

img.Image _boxImage({int size = 128, int inset = 24, int stroke = 3}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
  final lo = inset;
  final hi = size - inset - 1;
  for (var t = 0; t < stroke; t++) {
    for (var x = lo; x <= hi; x++) {
      im.setPixelRgba(x, lo + t, 0, 0, 0, 255);
      im.setPixelRgba(x, hi - t, 0, 0, 0, 255);
    }
    for (var y = lo; y <= hi; y++) {
      im.setPixelRgba(lo + t, y, 0, 0, 0, 255);
      im.setPixelRgba(hi - t, y, 0, 0, 0, 255);
    }
  }
  return im;
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('dohan_cli_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('buildDohan은 도안 패키지 세 파일을 만든다', () async {
    final input = File('${tmp.path}/in.png')
      ..writeAsBytesSync(img.encodePng(_boxImage()));
    final outDir = Directory('${tmp.path}/out');

    final report = await cli.buildDohan(
      input: input,
      outDir: outDir,
      id: 'box-01',
      title: '네모',
      category: 'animal',
      thresholds: const QualityThresholds(
        minRegions: 1,
        minBackgroundRatio: 0.0,
        minTapDiameterPx: 4,
      ),
    );

    expect(report.passed, isTrue, reason: report.koreanSummary());
    expect(File('${outDir.path}/lineart.png').existsSync(), isTrue);
    expect(File('${outDir.path}/regions.png').existsSync(), isTrue);
    expect(File('${outDir.path}/meta.json').existsSync(), isTrue);

    final pkg = await readDohanPackage(outDir);
    expect(pkg.meta.id, 'box-01');
    expect(pkg.meta.title, '네모');
    expect(pkg.meta.source, 'bundled');
    expect(pkg.meta.regionCount, 1);
    expect(pkg.meta.regionCentroids.length, 1);
  });

  test('품질 게이트에 걸리면 패키지를 쓰지 않는다', () async {
    // 선이 전혀 없는 흰 이미지 → 칠할 영역이 없다.
    final blank = img.Image(width: 64, height: 64, numChannels: 4);
    img.fill(blank, color: img.ColorRgba8(255, 255, 255, 255));
    final input = File('${tmp.path}/blank.png')
      ..writeAsBytesSync(img.encodePng(blank));
    final outDir = Directory('${tmp.path}/out');

    final report = await cli.buildDohan(
      input: input,
      outDir: outDir,
      id: 'blank',
      title: '빈 도안',
      category: 'animal',
    );

    expect(report.passed, isFalse);
    expect(outDir.existsSync(), isFalse,
        reason: '리젝트된 도안은 디스크에 남기지 않는다');
  });

  test('캔버스를 정규화하고 @2x 선화를 함께 쓴다', () async {
    final input = File('${tmp.path}/in.png')
      ..writeAsBytesSync(img.encodePng(_boxImage(size: 200)));
    final outDir = Directory('${tmp.path}/out');

    final report = await cli.buildDohan(
      input: input,
      outDir: outDir,
      id: 'norm-01',
      title: '정규화',
      category: 'animal',
      canvasSize: 128,
      thresholds: const QualityThresholds(
        minRegions: 1,
        minBackgroundRatio: 0.0,
        minTapDiameterPx: 4,
      ),
    );

    expect(report.passed, isTrue, reason: report.koreanSummary());

    final pkg = await readDohanPackage(outDir);
    expect(pkg.meta.canvasSize, [128, 128],
        reason: '입력이 200px여도 캔버스 크기로 정규화된다');
    expect(pkg.regions.width, 128);
    expect(pkg.lineart.width, 128);

    final at2x = img.decodePng(
        File('${outDir.path}/lineart@2x.png').readAsBytesSync())!;
    expect(at2x.width, 256, reason: '@2x는 캔버스의 2배 해상도다');
  });

  test('writePreview는 검수 이미지를 만든다', () async {
    final input = File('${tmp.path}/in.png')
      ..writeAsBytesSync(img.encodePng(_boxImage()));
    final out = File('${tmp.path}/preview.png');

    await cli.writePreview(input: input, output: out);

    expect(out.existsSync(), isTrue);
    expect(img.decodePng(out.readAsBytesSync())!.width, 128);
  });

  group('기본 ID', () {
    test('확장자만 떼고 점이 여럿인 이름을 보존한다', () {
      expect(cli.defaultIdFor(File('/tmp/cat.v2.final.png')), 'cat.v2.final');
      expect(cli.defaultIdFor(File('/tmp/cat.png')), 'cat');
      expect(cli.defaultIdFor(File('/tmp/noext')), 'noext');
    });
  });

  group('CLI 명령 계층', () {
    test('잘못된 --canvas-size 는 스택 트레이스 대신 65 를 돌려준다', () async {
      final input = File('${tmp.path}/in.png')
        ..writeAsBytesSync(img.encodePng(_boxImage()));

      final code = await cli.runDohan(
          ['build', input.path, '${tmp.path}/out', '--canvas-size=abc']);

      expect(code, 65);
      expect(Directory('${tmp.path}/out').existsSync(), isFalse);
    });

    test('허용하지 않는 --category 는 64 를 돌려준다', () async {
      final input = File('${tmp.path}/in.png')
        ..writeAsBytesSync(img.encodePng(_boxImage()));

      final code = await cli.runDohan(
          ['build', input.path, '${tmp.path}/out', '--category=우주선']);

      expect(code, 64);
    });

    test('인자 개수가 틀리면 64 를 돌려준다', () async {
      expect(await cli.runDohan(['build', 'only-one-arg']), 64);
    });

    test('품질 게이트가 거부하면 1 을 돌려준다', () async {
      final blank = img.Image(width: 64, height: 64, numChannels: 4);
      img.fill(blank, color: img.ColorRgba8(255, 255, 255, 255));
      final input = File('${tmp.path}/blank.png')
        ..writeAsBytesSync(img.encodePng(blank));

      final code = await cli.runDohan(
          ['build', input.path, '${tmp.path}/out', '--canvas-size=64']);

      expect(code, 1);
      expect(Directory('${tmp.path}/out').existsSync(), isFalse);
    });
  });

  test('세로로 긴 원본도 정사각 캔버스에 비율을 지켜 들어간다', () async {
    // 128x256 원본을 256 캔버스에 넣는다. 확대·축소가 없으므로 이 테스트는
    // 순수하게 여백 채우기와 가운데 정렬만 검증한다.
    final tall = img.Image(width: 128, height: 256, numChannels: 4);
    img.fill(tall, color: img.ColorRgba8(255, 255, 255, 255));
    for (var t = 0; t < 3; t++) {
      for (var x = 20; x <= 107; x++) {
        tall.setPixelRgba(x, 40 + t, 0, 0, 0, 255);
        tall.setPixelRgba(x, 215 - t, 0, 0, 0, 255);
      }
      for (var y = 40; y <= 215; y++) {
        tall.setPixelRgba(20 + t, y, 0, 0, 0, 255);
        tall.setPixelRgba(107 - t, y, 0, 0, 0, 255);
      }
    }
    final input = File('${tmp.path}/tall.png')
      ..writeAsBytesSync(img.encodePng(tall));
    final outDir = Directory('${tmp.path}/out');

    final report = await cli.buildDohan(
      input: input,
      outDir: outDir,
      id: 'tall-01',
      title: '세로',
      category: 'animal',
      canvasSize: 256,
      thresholds: const QualityThresholds(
        minRegions: 1,
        minBackgroundRatio: 0.0,
        minTapDiameterPx: 4,
      ),
    );

    expect(report.passed, isTrue, reason: report.koreanSummary());

    final pkg = await readDohanPackage(outDir);
    expect(pkg.regions.width, 256);
    expect(pkg.regions.height, 256);
    expect(pkg.regions.at(1, 128), kRegionBackground,
        reason: '왼쪽 여백은 배경이어야 한다');
    expect(pkg.regions.at(254, 128), kRegionBackground,
        reason: '오른쪽 여백은 배경이어야 한다');
    expect(pkg.regions.at(128, 128),
        greaterThanOrEqualTo(kRegionFirstFillable),
        reason: '가운데 도형 내부는 칠할 수 있어야 한다');
  });
}
