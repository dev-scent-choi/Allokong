import 'dart:io';
import 'dart:typed_data';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_route.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/settings/settings.dart';
import 'package:kkumul/ui/tool_bar.dart';

class FakeDohanSource implements DohanSource {
  @override
  Future<List<String>> listIds() async => ['fake'];

  @override
  Future<DohanMeta> loadMeta(String id) async => (await load(id)).meta;

  @override
  Future<DohanPackage> load(String id) async {
    const n = 64;
    final ids = Uint16List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        ids[y * n + x] = x < n ~/ 2 ? 2 : 3;
      }
    }
    return DohanPackage(
      meta: DohanMeta(
        id: 'fake',
        title: '가짜',
        category: 'animal',
        source: 'bundled',
        canvasSize: const [n, n],
        regionCount: 2,
        difficulty: 1,
        suggestedPalette: const [],
        regionAnchors: const {},
        createdAt: DateTime.utc(2026, 10, 6),
      ),
      lineart: img.Image(width: n, height: n, numChannels: 4),
      regions: RegionMap(n, n, ids),
    );
  }
}

/// 도안을 끝내 읽지 못하는 소스. 업데이트에서 빠졌거나 에셋이 깨진 경우다.
class ThrowingDohanSource implements DohanSource {
  @override
  Future<List<String>> listIds() async => [];

  @override
  Future<DohanMeta> loadMeta(String id) async => throw StateError('없는 도안');

  @override
  Future<DohanPackage> load(String id) async => throw StateError('없는 도안');
}

/// 엔진 콜백(ui.decodeImageFromPixels)은 testWidgets 본문의 FakeAsync
/// 아래에서 완료되지 않는다. 실제 존에서 한 박자 돌려 준 뒤 펌프한다.
Future<void> _settle(WidgetTester tester, [Finder? until]) async {
  // **`pumpAndSettle` 을 쓰지 않는다.** 여는 동안 도는
  // `CircularProgressIndicator` 가 프레임을 끝없이 예약해서 영영 멎지 않고,
  // 기본 타임아웃 10분까지 교착한다 — 태스크 5 에서 실제로 그랬다.
  //
  // 엔진 콜백(셰이더 컴파일·텍스처 디코딩)은 FakeAsync 아래에서 완료되지
  // 않으므로 실제 존에서 기다리며 펌프한다. 한 번으로는 모자라다 —
  // 여러 번에 나눠 끝난다(태스크 4 실측).
  for (var i = 0; i < 200; i++) {
    if (until != null && until.evaluate().isNotEmpty) break;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)));
    // **시간을 주어 펌프한다.** 인자 없는 pump() 는 시계를 움직이지 않아
    // 라우트 전환 애니메이션이 영영 안 끝나고, 들어오는 화면의 버튼이
    // 화면 밖에 머문 채로 남는다 — 태스크 5 에서 실제로 그랬다.
    await tester.pump(const Duration(milliseconds: 25));
    if (until == null && i >= 59) break; // 조건이 없으면 1.5초로 끝낸다
  }
  // 조건이 섰어도 라우트 전환은 아직 날아가는 중일 수 있다. 끝까지 밀어야
  // 버튼과 캔버스가 제자리에 온다 — 그 전에 getRect 로 좌표를 재면 화면
  // 밖을 짚는다(태스크 5 에서 완성 버튼이 x=904, 폭 800 화면 밖이었다).
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _canvas = find.byKey(const ValueKey('coloring-canvas'));

/// 색칠에서 셸로 돌아오기를 기다린다.
Future<void> _back(WidgetTester tester) => _settle(tester, find.text('열기'));

/// pop 이 몇 번 일어났는지 센다.
class _PopCounter extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  late Directory root;
  late ArtworkRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_route_');
    repository = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// 버튼 하나뿐인 집. 누르면 색칠을 띄운다.
  Widget host({
    required String artworkId,
    AgeMode ageMode = AgeMode.toddler,
    NavigatorObserver? observer,
    DohanSource? source,
  }) {
    return MaterialApp(
      navigatorObservers: [if (observer != null) observer],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openColoring(
              context,
              source: source ?? FakeDohanSource(),
              repository: repository,
              ageMode: ageMode,
              dohanId: 'fake',
              artworkId: artworkId,
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
  }

  /// 캔버스 왼쪽(영역 2)을 칠한다.
  Future<void> paintLeft(WidgetTester tester) async {
    final box = tester.getRect(_canvas);
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();
  }

  testWidgets('여는 동안 로딩을 보여주고 열리면 캔버스가 뜬다', (tester) async {
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await tester.pump(); // 라우트가 쌓인다
    await tester.pump(const Duration(milliseconds: 16)); // 첫 프레임이 그려진다

    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'open() 이 끝나기 전에는 로딩을 보여준다');

    await _settle(tester, _canvas);

    expect(_canvas, findsOneWidget);
  });

  testWidgets('완성을 누르면 셸로 돌아가고 칠한 것이 저장된다', (tester) async {
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);

    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _back(tester);

    expect(find.text('열기'), findsOneWidget, reason: '셸로 돌아와야 한다');
    // 진짜 파일 I/O 는 FakeAsync 아래에서 끝나지 않는다. 실제 존에서 읽는다.
    final saved = await tester.runAsync(() => repository.load('w1'));
    expect(saved, isNotNull);
    expect(saved!.fills, isNotEmpty);
  });

  testWidgets('나갔다 다시 들어오면 칠한 것이 그대로다', (tester) async {
    // 설계 스펙 2.3 이 "확인 없이 나가도 된다" 고 한 근거 그 자체다.
    // 잃는 것이 없어야 확인 대화상자를 뺄 수 있다.
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);
    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _back(tester);

    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);

    // 왼쪽 절반(영역 2)이 이미 칠해져 있으므로 다시 칠해도 늘지 않는다.
    // 진짜 파일 I/O 는 FakeAsync 아래에서 끝나지 않는다. 실제 존에서 읽는다.
    final saved = await tester.runAsync(() => repository.load('w1'));
    expect(saved!.fills.keys, contains(2),
        reason: '다시 열었을 때 칠한 것이 돌아와야 한다');

    await tester.tap(find.text('완성'));
    await _back(tester);
    expect(
      (await tester.runAsync(() => repository.load('w1')))!.fills.keys,
      contains(2),
    );
  });

  testWidgets('두 번째 작품도 저장된다', (tester) async {
    // Autosave 를 세션끼리 돌려 쓰면 첫 세션의 dispose() 가 그것을
    // dispose 해 버려, 두 번째부터 schedule() 이 조용히 아무 일도 하지
    // 않는다. 오류도 안 뜨고 그림만 사라진다.
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);
    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _back(tester);

    await tester.pumpWidget(host(artworkId: 'w2'));
    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);
    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _back(tester);

    expect((await tester.runAsync(() => repository.load('w1')))?.fills,
        isNotEmpty);
    expect((await tester.runAsync(() => repository.load('w2')))?.fills,
        isNotEmpty,
        reason: '두 번째 세션의 Autosave 가 죽어 있으면 여기서 빈다');
  });

  testWidgets('연령대를 바꿔 열면 그 설정이 적용된다', (tester) async {
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);
    expect(find.byType(ToolButton), findsNothing, reason: '유아는 도구 줄이 없다');
    await tester.tap(find.text('완성'));
    await _back(tester);

    await tester.pumpWidget(host(artworkId: 'w2', ageMode: AgeMode.child));
    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);

    expect(find.byType(ToolButton), findsNWidgets(5),
        reason: '새 세션은 새 컨트롤러라 현재 설정을 읽는다');
  });

  testWidgets('저장 파일을 읽지 못하면 복구 id 로 연다', (tester) async {
    // main() 에 있던 복구 경로다. 같은 id 로 새로 시작하면 자동 저장이
    // 잠깐 못 읽었을 뿐일지 모르는 멀쩡한 파일을 덮어쓴다.
    //
    // **내용이 깨진 JSON 으로는 이 경로를 못 건드린다** — `load()` 가
    // FormatException 을 잡아 null 을 주므로 복구가 아예 안 돈다(실측).
    // 던지는 것은 읽기 자체의 실패뿐이다. artwork.json 자리에 디렉터리를
    // 두면 readAsString 이 FileSystemException(PathNotFoundException 이
    // 아니다)을 내고 `load()` 가 그대로 올려 보낸다 — 권한·잠김·디스크
    // 오류가 실제로 그렇게 온다.
    Directory('${root.path}/artworks/w1/artwork.json')
        .createSync(recursive: true);

    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);
    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _back(tester);

    final ids = (await tester.runAsync(() => repository.listAll()))!
        .map((a) => a.id)
        .toList();
    expect(ids.where((id) => id.startsWith('w1-복구-')), hasLength(1));
    expect(Directory('${root.path}/artworks/w1/artwork.json').existsSync(),
        isTrue, reason: '원본은 손대지 않는다');
  });

  testWidgets('도안을 끝내 못 열면 돌아갈 버튼이 뜨고 누르면 셸로 돌아온다', (tester) async {
    // 스피너만 돌리면 그 화면에는 앱바도 완성 버튼도 PopScope 도 없어
    // 글을 못 읽는 아이가 갇힌다.
    await tester.pumpWidget(
        host(artworkId: 'w1', source: ThrowingDohanSource()));
    await tester.tap(find.text('열기'));
    final back = find.byKey(const ValueKey('open-failed-back'));
    await _settle(tester, back);

    expect(back, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(back);
    await _back(tester);

    expect(find.text('열기'), findsOneWidget, reason: '셸로 돌아와야 한다');
  });

  testWidgets('완성을 두 번 눌러도 pop 은 한 번이다', (tester) async {
    // 아이는 버튼을 두 번 누른다. 첫 pop 뒤에도 나가는 전환 동안 위젯이
    // 살아 있어 mounted 가 참이라, 막지 않으면 두 번째 pop 이 그 아래의
    // 셸까지 닫는다.
    final pops = _PopCounter();
    await tester.pumpWidget(host(artworkId: 'w1', observer: pops));
    await tester.tap(find.text('열기'));
    await _settle(tester, _canvas);

    final finish = find.text('완성');
    await tester.tap(finish, warnIfMissed: false);
    if (finish.evaluate().isNotEmpty) {
      await tester.tap(finish, warnIfMissed: false);
    }
    await _back(tester);

    expect(pops.pops, 1, reason: '색칠 화면 하나만 닫혀야 한다');
  });

  test('작품 id 는 빠르게 두 번 만들어도 겹치지 않는다', () {
    final ids = {for (var i = 0; i < 50; i++) newArtworkId('flower-01')};
    expect(ids, hasLength(50));
    expect(ids.every((id) => id.startsWith('flower-01-')), isTrue);
  });
}
