import 'dart:io';

import 'package:dohan_core/dohan_core.dart';
import 'package:dohan_core/dohan_core_io.dart';
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

/// 떨어져 있는 정사각형 네 개. 기본 품질 게이트를 통과하는 픽스처다.
///
/// 동심원으로 겹쳐 그리면 배경이 바깥 테두리 한 겹뿐이라 60% 기준을 못 넘고,
/// 고리 폭도 72px 터치 기준에 못 미친다. 네 개를 떼어 놓으면 배경이 캔버스
/// 대부분을 차지하면서 각 내부가 100px 폭을 갖는다.
/// 측정값: 영역 4개, 배경 82.9%, 최소 지름 99px.
img.Image _fourBoxesImage({int size = 512}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
  const side = 106;
  const hi = side - 1;
  for (final oy in [60, 300]) {
    for (final ox in [60, 300]) {
      for (var t = 0; t < 3; t++) {
        for (var d = 0; d <= hi; d++) {
          im.setPixelRgba(ox + d, oy + t, 0, 0, 0, 255);
          im.setPixelRgba(ox + d, oy + hi - t, 0, 0, 0, 255);
          im.setPixelRgba(ox + t, oy + d, 0, 0, 0, 255);
          im.setPixelRgba(ox + hi - t, oy + d, 0, 0, 0, 255);
        }
      }
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
    expect(pkg.meta.regionAnchors.length, 1);
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

  test('writePreview는 캔버스 크기로 정규화한 검수 이미지를 만든다', () async {
    final input = File('${tmp.path}/in.png')
      ..writeAsBytesSync(img.encodePng(_boxImage()));
    final out = File('${tmp.path}/preview.png');

    await cli.writePreview(input: input, output: out, canvasSize: 256);

    expect(out.existsSync(), isTrue);
    expect(img.decodePng(out.readAsBytesSync())!.width, 256);
  });

  test('build 가 쓴 lineart.png 를 preview 가 그대로 읽는다', () async {
    // lineart.png 는 투명 배경이다. 알파를 무시하면 빈 페이지가 나온다.
    final input = File('${tmp.path}/src.png')
      ..writeAsBytesSync(img.encodePng(_fourBoxesImage()));
    final outDir = Directory('${tmp.path}/out');
    final report = await cli.buildDohan(
      input: input,
      outDir: outDir,
      id: 'rt',
      title: 'rt',
      category: 'animal',
      canvasSize: 512,
    );
    expect(report.passed, isTrue, reason: report.koreanSummary());

    final preview = File('${tmp.path}/check.png');
    await cli.writePreview(
      input: File('${outDir.path}/lineart.png'),
      output: preview,
      canvasSize: 512,
    );

    final im = img.decodePng(preview.readAsBytesSync())!;
    final colours = <String>{};
    for (var y = 0; y < im.height; y += 7) {
      for (var x = 0; x < im.width; x += 7) {
        final p = im.getPixel(x, y);
        colours.add('${p.r}-${p.g}-${p.b}');
      }
    }
    expect(colours.length, greaterThan(3),
        reason: '빈 페이지가 아니라 영역별로 다른 색이 보여야 한다');
  });

  group('기본 ID', () {
    test('확장자만 떼고 점이 여럿인 이름을 보존한다', () {
      expect(cli.defaultIdFor(File('/tmp/cat.v2.final.png')), 'cat.v2.final');
      expect(cli.defaultIdFor(File('/tmp/cat.png')), 'cat');
      expect(cli.defaultIdFor(File('/tmp/noext')), 'noext');
      expect(cli.defaultIdFor(File('/tmp/.gitkeep')), '.gitkeep',
          reason: '점으로 시작하는 이름은 확장자가 아니라 이름 전체다');
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

    test('음수 임계값은 조용히 넘어가지 않고 65 를 돌려준다', () async {
      // 범위를 안 보면 음수가 해당 게이트를 무력화해, 오타가 "통과"로 보인다.
      final input = File('${tmp.path}/in.png')
        ..writeAsBytesSync(img.encodePng(_boxImage()));

      for (final bad in [
        '--min-tap-diameter=-5',
        '--min-region-area=0',
        '--canvas-size=0',
        '--difficulty=9',
        '--close-radius=-1',
      ]) {
        final code = await cli.runDohan(
            ['build', input.path, '${tmp.path}/out', bad]);
        expect(code, 65, reason: '$bad 는 거부돼야 한다');
      }
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

    test('정상 빌드는 0 을 돌려주고 파일 이름에서 ID 를 채운다', () async {
      // 파일 이름에 점이 여럿 — 명령 계층이 확장자만 떼는지 함께 확인한다.
      final input = File('${tmp.path}/cat.v2.final.png')
        ..writeAsBytesSync(img.encodePng(_fourBoxesImage()));
      final outDir = Directory('${tmp.path}/out');

      final code = await cli.runDohan([
        'build',
        input.path,
        outDir.path,
        '--canvas-size=512',
        '--category=animal',
      ]);

      expect(code, 0, reason: '품질 게이트를 통과한 빌드는 0 이어야 한다');

      final pkg = await readDohanPackage(outDir);
      expect(pkg.meta.id, 'cat.v2.final',
          reason: '기본 ID 는 마지막 확장자만 떼야 한다');
      expect(pkg.meta.title, 'cat.v2.final',
          reason: '--title 을 주지 않으면 ID 를 쓴다');
      expect(pkg.meta.category, 'animal');
      expect(pkg.meta.canvasSize, [512, 512]);
      expect(File('${outDir.path}/lineart@2x.png').existsSync(), isTrue);
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
