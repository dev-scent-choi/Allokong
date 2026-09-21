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
}
