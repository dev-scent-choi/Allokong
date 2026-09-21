import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;

/// 원본을 정사각 캔버스에 흰 여백과 함께 비율을 지켜 맞춰 넣는다.
///
/// 입력 이미지의 크기와 비율이 제각각이어도 도안 캔버스는 항상 같아야
/// 한다. 잘라내지 않고 여백을 주는 이유는 그림이 잘리면 안 되기 때문이다.
img.Image _fitToCanvas(img.Image src, int size) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  final longest = src.width > src.height ? src.width : src.height;
  final scale = size / longest;
  final w = (src.width * scale).round();
  final h = (src.height * scale).round();
  final resized = img.copyResize(
    src,
    width: w,
    height: h,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    resized,
    dstX: (size - w) ~/ 2,
    dstY: (size - h) ~/ 2,
  );
  return canvas;
}

/// 선 마스크를 알파 채널이 있는 검정 선화 이미지로 바꾼다.
img.Image _inkToImage(BinaryMask mask) {
  final im = img.Image(width: mask.width, height: mask.height, numChannels: 4);
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      im.setPixelRgba(x, y, 0, 0, 0, mask.isInk(x, y) ? 255 : 0);
    }
  }
  return im;
}

/// 선화 파일 하나를 도안 패키지로 변환한다.
///
/// 품질 게이트를 통과한 경우에만 [outDir]에 파일을 쓴다. 리젝트된 도안이
/// 디스크에 남으면 나중에 실수로 앱에 포함될 수 있다.
Future<QualityReport> buildDohan({
  required File input,
  required Directory outDir,
  required String id,
  required String title,
  required String category,
  int canvasSize = 1024,
  int difficulty = 1,
  List<String> suggestedPalette = const ['#ef7586', '#f1bd45', '#6caee0'],
  QualityThresholds thresholds = const QualityThresholds(),
}) async {
  final source = img.decodeImage(await input.readAsBytes());
  if (source == null) {
    throw FormatException('이미지를 읽을 수 없습니다: ${input.path}');
  }

  final fitted = _fitToCanvas(source, canvasSize);
  final result = runPipeline(
    fitted,
    options: PipelineOptions(thresholds: thresholds),
  );
  if (!result.quality.passed) return result.quality;

  // 선화는 원본이 아니라 보정된 마스크로 다시 그린다. 원본의 회색 얼룩을
  // 남기지 않기 위해서이며, 영역 경계와 선이 정확히 일치해야 채움이 새지
  // 않는다.
  await writeDohanPackage(
    dir: outDir,
    lineart: _inkToImage(result.ink),
    regions: result.regions,
    meta: DohanMeta(
      id: id,
      title: title,
      category: category,
      source: 'bundled',
      canvasSize: [canvasSize, canvasSize],
      regionCount: result.regions.fillableRegionCount,
      difficulty: difficulty,
      suggestedPalette: suggestedPalette,
      regionCentroids: computeRegionCentroids(result.regions),
      createdAt: DateTime.now().toUtc(),
    ),
  );

  // 고밀도 기기용 선화. 영역 라벨링은 1배 해상도에서 한 번만 하고, 여기서는
  // 선만 2배로 다시 뽑는다. 두 해상도의 경계가 1픽셀 어긋나도 선 두께 안에
  // 묻히므로 채움이 비어 보이지 않는다.
  final ink2x = closeLines(binarize(_fitToCanvas(source, canvasSize * 2)));
  await File('${outDir.path}/lineart@2x.png')
      .writeAsBytes(img.encodePng(_inkToImage(ink2x), level: 9));

  return result.quality;
}

/// 영역 분리 상태를 눈으로 확인할 검수 이미지를 쓴다.
Future<void> writePreview({
  required File input,
  required File output,
}) async {
  final source = img.decodeImage(await input.readAsBytes());
  if (source == null) {
    throw FormatException('이미지를 읽을 수 없습니다: ${input.path}');
  }
  final result = runPipeline(source);
  await output.writeAsBytes(
    img.encodePng(renderRegionPreview(result.regions), level: 9),
  );
}

class _BuildCommand extends Command<int> {
  @override
  final name = 'build';
  @override
  final description = '선화 이미지를 도안 패키지로 변환합니다.';

  _BuildCommand() {
    argParser
      ..addOption('id', help: '도안 ID. 생략하면 파일 이름을 씁니다.')
      ..addOption('title', help: '도안 제목. 생략하면 ID를 씁니다.')
      ..addOption('category',
          allowed: ['animal', 'car', 'dinosaur', 'character'],
          defaultsTo: 'animal',
          help: '도안 카테고리.')
      ..addOption('difficulty', defaultsTo: '1', help: '난이도 1~3.')
      ..addOption('canvas-size',
          defaultsTo: '1024', help: '정사각 캔버스 한 변의 픽셀 수.');
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      stderr.writeln('사용법: dohan build <입력.png> <출력디렉터리>');
      return 64;
    }
    final input = File(rest[0]);
    final outDir = Directory(rest[1]);
    final id = (argResults!['id'] as String?) ??
        input.uri.pathSegments.last.split('.').first;
    final title = (argResults!['title'] as String?) ?? id;

    final report = await buildDohan(
      input: input,
      outDir: outDir,
      id: id,
      title: title,
      category: argResults!['category'] as String,
      canvasSize: int.parse(argResults!['canvas-size'] as String),
      difficulty: int.parse(argResults!['difficulty'] as String),
    );

    stdout.writeln('$id: ${report.koreanSummary()}');
    return report.passed ? 0 : 1;
  }
}

class _PreviewCommand extends Command<int> {
  @override
  final name = 'preview';
  @override
  final description = '영역 분리 상태를 색으로 보여주는 검수 이미지를 만듭니다.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      stderr.writeln('사용법: dohan preview <입력.png> <출력.png>');
      return 64;
    }
    await writePreview(input: File(rest[0]), output: File(rest[1]));
    stdout.writeln('검수 이미지를 썼습니다: ${rest[1]}');
    return 0;
  }
}

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('dohan', '도안 에셋 파이프라인 도구')
    ..addCommand(_BuildCommand())
    ..addCommand(_PreviewCommand());
  exitCode = await runner.run(args) ?? 0;
}
