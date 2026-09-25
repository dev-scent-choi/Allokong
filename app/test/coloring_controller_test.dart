import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/coloring_controller.dart';
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/gallery/autosave.dart';
import 'package:image/image.dart' as img;

/// 좌/우 두 영역만 있는 가짜 도안. 에셋 없이 컨트롤러를 시험한다.
class FakeDohanSource implements DohanSource {
  @override
  Future<List<String>> listIds() async => ['fake'];

  @override
  Future<DohanPackage> load(String id) async {
    const w = 4, h = 2;
    final ids = Uint16List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        ids[y * w + x] = x < 2 ? 2 : 3;
      }
    }
    return DohanPackage(
      meta: DohanMeta(
        id: 'fake',
        title: '가짜',
        category: 'animal',
        source: 'bundled',
        canvasSize: const [w, h],
        regionCount: 2,
        difficulty: 1,
        suggestedPalette: const ['#ef7586'],
        regionAnchors: const {},
        createdAt: DateTime.utc(2026, 9, 25),
      ),
      lineart: img.Image(width: w, height: h, numChannels: 4),
      regions: RegionMap(w, h, ids),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ColoringController c;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('kkumul_ctl_');
    c = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(
        repository: ArtworkRepository(root),
        debounce: const Duration(milliseconds: 20),
      ),
    );
    await c.open(dohanId: 'fake', artworkId: 'w1');
  });
  tearDown(() async {
    await c.close();
    root.deleteSync(recursive: true);
  });

  test('도안을 열면 준비 상태가 된다', () {
    expect(c.isReady, isTrue);
    expect(c.dohan!.meta.id, 'fake');
    expect(c.fills.filledCount, 0);
  });

  test('탭하면 그 영역이 선택한 색으로 칠해진다', () {
    c.pickColor(const Color(0xFFEF7586));

    expect(c.tapAt(const Offset(0.5, 0.5)), isTrue);

    expect(c.fills.fillOf(2), const Color(0xFFEF7586));
    expect(c.fills.fillOf(3), isNull);
  });

  test('영역마다 다른 색을 칠할 수 있다', () {
    c.pickColor(const Color(0xFFEF7586));
    c.tapAt(const Offset(0.5, 0.5));
    c.pickColor(const Color(0xFF6CAEE0));
    c.tapAt(const Offset(3.5, 0.5));

    expect(c.fills.fillOf(2), const Color(0xFFEF7586));
    expect(c.fills.fillOf(3), const Color(0xFF6CAEE0));
  });

  test('같은 색을 다시 칠하면 아무 일도 없다', () {
    c.pickColor(const Color(0xFFEF7586));
    c.tapAt(const Offset(0.5, 0.5));

    expect(c.tapAt(const Offset(0.5, 0.5)), isFalse,
        reason: '되돌리기 스택을 의미 없이 채우지 않는다');
    expect(c.canUndo, isTrue);
  });

  test('캔버스 밖을 누르면 아무 일도 없다', () {
    c.pickColor(const Color(0xFFEF7586));

    expect(c.tapAt(const Offset(-5, -5)), isFalse);
    expect(c.fills.filledCount, 0);
    expect(c.canUndo, isFalse);
  });

  test('되돌리면 직전 상태로 간다', () {
    c.pickColor(const Color(0xFFEF7586));
    c.tapAt(const Offset(0.5, 0.5));

    expect(c.undo(), isTrue);

    expect(c.fills.fillOf(2), isNull);
    expect(c.canUndo, isFalse);
  });

  test('칠하면 자동 저장이 예약되고, 닫으면 파일이 남는다', () async {
    c.pickColor(const Color(0xFFEF7586));
    c.tapAt(const Offset(0.5, 0.5));

    await c.close();

    final saved = await ArtworkRepository(root).load('w1');
    expect(saved, isNotNull);
    expect(saved!.dohanId, 'fake');
    expect(saved.fills[2], const Color(0xFFEF7586).toARGB32());
  });

  test('저장된 작품을 열면 칠한 것이 되살아난다', () async {
    final restored = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(repository: ArtworkRepository(root)),
    );
    addTearDown(restored.close);

    await restored.open(
      dohanId: 'fake',
      artworkId: 'w2',
      existing: Artwork(
        id: 'w2',
        dohanId: 'fake',
        fills: {2: const Color(0xFF63B98B).toARGB32()},
        updatedAt: DateTime.utc(2026, 9, 25),
      ),
    );

    expect(restored.fills.fillOf(2), const Color(0xFF63B98B));
    expect(restored.canUndo, isFalse, reason: '불러온 상태는 되돌릴 대상이 아니다');
  });
}
