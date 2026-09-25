# 색칠 엔진과 앱 셸 구현 계획 (계획 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 내장 도안을 띄우고, 탭해서 칠하고, 앱을 껐다 켜도 칠한 것이 남아 있는 Flutter 앱을 만든다.

**Architecture:** `dohan_core`(계획 1에서 완성)가 산출한 도안 패키지를 에셋으로 싣고, 인덱스맵을 fragment shader로 샘플링해 채움 레이어를 그린다. 탭 좌표를 캔버스 좌표로 바꿔 인덱스맵에서 영역 ID를 O(1)로 읽고, 256×256 팔레트 LUT의 해당 픽셀 하나만 갱신해 다시 그린다. 작품은 폴더 하나에 자기 완결적으로 저장하고 명령 단위로 자동 저장한다.

**Tech Stack:** Flutter 3.47.5 · Dart 3.13.4 · `dohan_core` (path 의존) · GLSL fragment shader · 파일 시스템 저장(DB 없음)

**Spec:** [docs/superpowers/specs/2026-09-21-kkumul-coloring-app-design.md](../specs/2026-09-21-kkumul-coloring-app-design.md) — 5·7·10·11장

**선행 계획:** [2026-09-21-dohan-core-pipeline.md](2026-09-21-dohan-core-pipeline.md) (완료). 후속 작업 목록은 [2026-09-21-dohan-core-pipeline-followups.md](2026-09-21-dohan-core-pipeline-followups.md).

## Global Constraints

스펙에서 그대로 옮긴 값들이다. 모든 태스크의 요구사항에 암묵적으로 포함된다.

- 영역 ID `0` = 선 픽셀 (칠할 수 없고 브러시도 얹히지 않는다)
- 영역 ID `1` = `BACKGROUND` (도안 바깥, 칠할 수 없다)
- 영역 ID `2` 이상 = 칠할 수 있는 영역
- 인덱스맵 인코딩: R = ID 하위 8bit, G = ID 상위 8bit, B = 0, A = 255
- 인덱스맵 해상도: 1024 × 1024 고정
- **인덱스맵은 반드시 nearest-neighbor로만 샘플링한다.** 선형 보간을 쓰면 영역 경계에서 ID 17과 23이 섞여 20이 산출되고 엉뚱한 영역이 칠해진다
- 팔레트 LUT: 256 × 256 RGBA 텍스처. 영역 ID `n`은 좌표 `(n % 256, n ~/ 256)`. 알파 0 = 아직 칠하지 않음
- 레이어 합성 순서 (아래→위): 흰 배경 → 채움 → 브러시 → 선화 → 스티커
- 터치 타겟 최소 64dp (UI 컨트롤 기준)
- 사용자 대면 문자열은 한국어
- 네트워크를 쓰지 않는다. 개인정보를 수집하지 않는다

## 계획 2의 범위

이 계획은 **가장 얇은 완결 수직 슬라이스**다.

**포함:** 내장 도안 로드 · 탭 채우기 · 되돌리기 · 작품 저장 · 자동 저장 · 색칠 화면 하나

**제외 (후속 계획):** 브러시·크레용·스티커·지우개(계획 3) · 사진→도안 변환(계획 4) · 5탭 내비게이션·갤러리·랭크·공유·연령 분기(계획 5)

레이어 구조는 처음부터 스펙의 5층으로 잡되, 이 계획에서는 배경·채움·선화 세 층만 그린다. 브러시와 스티커 층은 계획 3이 끼워 넣는다.

---

## 시작 전 실측으로 확인된 것

계획을 쓰기 전에 Flutter 3.47.5에서 직접 돌려 확인했다. 아래 코드는 추측이 아니라 통과한 코드다.

| 확인한 것 | 결과 |
|---|---|
| `FragmentShader.setImageSampler` 필터 모드 | nearest. 원본에 없던 값이 나오지 않았다 |
| 텍셀 중심 스냅 | 필터 모드와 무관하게 정확. **이중 안전장치로 셰이더에 넣는다** |
| 16bit ID 디코딩 | 상위 바이트 경로(ID 300) 포함 정확 |
| 팔레트 LUT 조회 | 정확. 선(0)·배경(1)·미채색(알파 0) 모두 투명 |
| 캔버스 확대·이동 | `FlutterFragCoord()`가 로컬 좌표라 변환을 따라간다 |
| 팔레트 이미지 생성 비용 | 256×256 한 장당 0.21ms — 한 프레임의 1/75 |
| Windows에서 기존 파일 위 `rename` | 성공. 원자적 쓰기가 성립한다 |
| `flutter test`에서 에셋 로딩 | 성공 (단, UTF-8은 `utf8.decode`로 풀 것) |
| `decodeImageFromPixels` 의 버퍼 | **복사한다.** 콜백 전에 원본을 고쳐도 이미지는 안 바뀐다 — LUT 를 재사용해도 안전 |
| Windows path 의존성 | `pub get`·`test` 는 개발자 모드 없이 되고, `flutter run` 은 요구한다 |
| 계획서의 Dart 코드 13파일 | `flutter analyze` 통과 (이 검토에서 나온 지적 2건은 반영 완료) |

**텍셀 중심 스냅을 반드시 넣는다.** `setImageSampler`가 지금은 nearest지만 백엔드(Impeller/Skia)나 버전에 따라 달라질 수 있고, 어긋나면 스펙이 경고한 "조용히 발생하고 재현이 어려운" 버그가 된다. 스냅은 공짜이고 필터 모드를 무관하게 만든다.

---

## File Structure

```
app/                                  Flutter 앱 (새로 만든다)
  pubspec.yaml
  shaders/
    fill.frag                         채움 레이어 셰이더
  assets/dohans/flower-01/            내장 도안 한 벌
    lineart.png  regions.png  meta.json
  lib/
    main.dart                         앱 진입점
    core/
      artwork.dart                    Artwork 모델과 직렬화
      command.dart                    Command · FillCommand · UndoStack
      dohan_source.dart               DohanSource 인터페이스
    library/
      bundled_dohan_source.dart       에셋에서 도안 로드
    coloring/
      canvas_transform.dart           화면↔캔버스 좌표, 영역 ID 조회
      fill_state.dart                 fills 맵과 팔레트 LUT
      coloring_painter.dart           CustomPainter
      coloring_controller.dart        상태 묶음 (fills · undo · 저장)
    gallery/
      artwork_repository.dart         작품 폴더 저장·로드
      autosave.dart                   디바운스 자동 저장
    ui/
      coloring_screen.dart            화면 조립
      palette_bar.dart                색 고르기 UI
  test/
    canvas_transform_test.dart
    fill_state_test.dart
    fill_shader_test.dart
    command_test.dart
    artwork_repository_test.dart
    autosave_test.dart
    bundled_dohan_source_test.dart
    coloring_screen_test.dart
  tools/
    make_sample_lineart.dart          내장 도안용 합성 선화 생성기
```

각 파일이 한 가지 책임만 진다. `coloring/`은 저장을 모르고, `gallery/`는 렌더링을 모른다. `canvas_transform.dart`는 Flutter 위젯을 모르고 순수 계산만 한다 — 스펙 15장이 "최상" 우선순위로 꼽은 좌표 매핑을 위젯 없이 테스트하기 위해서다.

---

### Task 1: 앱 스켈레톤과 내장 도안 에셋

**Files:**
- Create: `app/` (flutter create)
- Modify: `app/pubspec.yaml`
- Create: `app/tools/make_sample_lineart.dart`
- Create: `app/assets/dohans/flower-01/{lineart.png,regions.png,meta.json}`
- Test: `app/test/smoke_test.dart`

**Interfaces:**
- Consumes: `packages/dohan_core` (path 의존), `tools/dohan_cli` (에셋 생성용, 런타임 의존 아님)
- Produces: 빌드되는 Flutter 앱 · `assets/dohans/flower-01/` 도안 한 벌 · `dohan_core`를 앱에서 import 가능

- [ ] **Step 1: Flutter 앱 생성**

저장소 루트에서:

```bash
flutter create --platforms=android,ios,windows --project-name kkumul app
```

**Windows 에서는 개발자 모드를 먼저 켠다.** path 의존성이 심볼릭 링크를 쓰므로 `flutter run` 이 개발자 모드를 요구한다. `start ms-settings:developers` 로 설정을 열어 켠다. (`flutter pub get` 과 `flutter test` 는 꺼져 있어도 동작한다 — 실측 확인.)

- [ ] **Step 2: pubspec 설정**

`app/pubspec.yaml`의 `dependencies`와 `flutter` 절을 아래처럼 만든다. `flutter create`가 넣은 `cupertino_icons`는 그대로 둔다.

```yaml
environment:
  sdk: ^3.13.0

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  dohan_core:
    path: ../packages/dohan_core
  image: ^4.2.0
  path_provider: ^2.1.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true

  assets:
    - assets/dohans/flower-01/
```

`shaders:` 절은 **여기 넣지 않는다.** Task 5 가 `fill.frag` 파일을 만들면서 함께 등록한다. 없는 셰이더를 pubspec 에 적어 두면 이 태스크의 `flutter test` 가 에셋 번들링에서 실패한다.

`image` 를 직접 넣는 이유는 `coloring_screen.dart` 가 선화를 PNG 로 인코딩할 때 쓰기 때문이다. `dohan_core` 를 통해 딸려 오긴 하지만, 직접 쓰는 패키지는 직접 선언해야 분석기가 조용하다.

`dohan_core_io.dart`는 쓰지 않는다 — 내장 도안은 에셋이라 `File`이 아니다. 앱이 import하는 것은 `package:dohan_core/dohan_core.dart` 하나뿐이다.

- [ ] **Step 3: 샘플 선화 생성기 작성**

`app/tools/make_sample_lineart.dart`:

```dart
// 내장 도안용 합성 선화를 만든다. 실제 도안 에셋이 준비되면 이 파일은 지운다.
//
// 동심원 네 겹 — 품질 게이트(영역 4개 이상, 최소 지름 72px)를 통과하는
// 가장 단순한 모양이다.
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  const size = 1024;
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));

  void ink(int x, int y) {
    if (x >= 0 && y >= 0 && x < size && y < size) {
      im.setPixelRgba(x, y, 0, 0, 0, 255);
    }
  }

  // 반지름이 다른 원 네 개. 굵기 6px.
  for (final radius in [460, 340, 220, 100]) {
    for (var d = 0; d < 7200; d++) {
      final rad = d / 7200.0 * 6.283185307179586;
      final cx = 512 + radius * _cos(rad);
      final cy = 512 + radius * _sin(rad);
      for (var dy = -3; dy <= 3; dy++) {
        for (var dx = -3; dx <= 3; dx++) {
          ink(cx.round() + dx, cy.round() + dy);
        }
      }
    }
  }

  final out = args.isEmpty ? 'sample_lineart.png' : args[0];
  File(out).writeAsBytesSync(img.encodePng(im, level: 9));
  stdout.writeln('wrote $out (${size}x$size)');
}

double _cos(double r) {
  var s = 1.0, t = 1.0;
  for (var n = 1; n < 15; n++) {
    t *= -r * r / ((2 * n - 1) * (2 * n));
    s += t;
  }
  return s;
}

double _sin(double r) {
  var s = r, t = r;
  for (var n = 1; n < 15; n++) {
    t *= -r * r / ((2 * n) * (2 * n + 1));
    s += t;
  }
  return s;
}
```

- [ ] **Step 4: 도안 에셋 생성**

```bash
cd app
dart run tools/make_sample_lineart.dart /tmp/sample.png
cd ../tools/dohan_cli
dart run bin/dohan.dart build /tmp/sample.png ../../app/assets/dohans/flower-01 \
    --id flower-01 --title "동그라미 꽃" --category animal --difficulty 1
```

Expected: `통과 — 영역 4개, 배경 ...%, 최소 영역 지름 ...px` 와 함께 네 파일이 생긴다.

품질 게이트에 걸리면 `make_sample_lineart.dart`의 반지름을 벌려 다시 만든다. **단언을 약화시키거나 임계값을 낮추지 말 것** — 게이트가 맞고 픽스처가 틀린 것이다.

- [ ] **Step 5: 스모크 테스트 작성**

`app/test/smoke_test.dart`:

```dart
import 'dart:convert';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('내장 도안 에셋이 실려 있고 dohan_core 로 읽힌다', () async {
    final metaBytes = await rootBundle.load('assets/dohans/flower-01/meta.json');
    final meta = DohanMeta.parse(
      utf8.decode(metaBytes.buffer.asUint8List()),
      label: 'assets/dohans/flower-01',
    );

    expect(meta.id, 'flower-01');
    expect(meta.canvasSize, [1024, 1024]);
    expect(meta.regionCount, greaterThanOrEqualTo(4));
  });
}
```

에셋 바이트를 문자열로 풀 때는 반드시 `utf8.decode`를 쓴다. `String.fromCharCodes`는 UTF-8을 바이트 단위로 읽어 한국어를 깨뜨린다.

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd app && flutter test test/smoke_test.dart
```

Expected: PASS — 1개 테스트 통과

- [ ] **Step 7: 커밋**

```bash
git add app
git commit -m "feat(app): Flutter 앱 스켈레톤과 내장 도안 에셋"
```

---

### Task 2: 도안 소스 — 에셋에서 도안 읽기

**Files:**
- Create: `app/lib/core/dohan_source.dart`
- Create: `app/lib/library/bundled_dohan_source.dart`
- Test: `app/test/bundled_dohan_source_test.dart`

**Interfaces:**
- Consumes: `DohanMeta`, `DohanPackage`, `DohanPackage.fromBytes({required String metaJson, required Uint8List lineartPng, required Uint8List regionsPng, String label})` (dohan_core)
- Produces: `abstract class DohanSource` (메서드 `Future<List<String>> listIds()`, `Future<DohanPackage> load(String id)`) · `class BundledDohanSource implements DohanSource` (생성자 `BundledDohanSource({AssetBundle? bundle, List<String> ids})`)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/bundled_dohan_source_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/library/bundled_dohan_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('내장 도안 목록을 돌려준다', () async {
    final source = BundledDohanSource();

    expect(await source.listIds(), contains('flower-01'));
  });

  test('에셋 바이트에서 도안 한 벌을 만든다', () async {
    final pkg = await BundledDohanSource().load('flower-01');

    expect(pkg.meta.id, 'flower-01');
    expect(pkg.regions.width, 1024);
    expect(pkg.regions.height, 1024);
    expect(pkg.lineart.width, 1024);
    expect(pkg.regions.fillableRegionCount, greaterThanOrEqualTo(4));
  });

  test('없는 도안은 한국어로 알려준다', () async {
    expect(
      () => BundledDohanSource().load('없는도안'),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message, 'message', contains('없는도안'))),
    );
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/bundled_dohan_source_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/library/bundled_dohan_source.dart'`

- [ ] **Step 3: 인터페이스 작성**

`app/lib/core/dohan_source.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';

/// 도안을 어디서 가져올지 감추는 경계.
///
/// 1단계 구현체는 앱에 내장된 에셋을 읽는 것 하나뿐이다. 사용자가 사진에서
/// 만든 도안(계획 4)과 원격 배포(미정)가 같은 인터페이스 뒤에 붙는다.
abstract class DohanSource {
  /// 이 소스가 가진 도안 ID 목록.
  Future<List<String>> listIds();

  /// 도안 한 벌을 읽는다. 없는 ID 면 [ArgumentError] 를 던진다.
  Future<DohanPackage> load(String id);
}
```

- [ ] **Step 4: 구현 작성**

`app/lib/library/bundled_dohan_source.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/services.dart';

import '../core/dohan_source.dart';

/// 앱 번들에 실린 도안을 읽는다.
///
/// 에셋은 `File` 이 아니므로 `readDohanPackage` 를 쓸 수 없다. 바이트를 받아
/// `DohanPackage.fromBytes` 로 조립한다.
class BundledDohanSource implements DohanSource {
  /// 번들에 실린 도안 ID. pubspec 의 `assets` 목록과 짝이 맞아야 한다.
  static const defaultIds = ['flower-01'];

  final AssetBundle _bundle;
  final List<String> _ids;

  BundledDohanSource({AssetBundle? bundle, List<String>? ids})
      : _bundle = bundle ?? rootBundle,
        _ids = ids ?? defaultIds;

  @override
  Future<List<String>> listIds() async => List.unmodifiable(_ids);

  @override
  Future<DohanPackage> load(String id) async {
    if (!_ids.contains(id)) {
      throw ArgumentError('내장 도안에 없는 ID 입니다: $id');
    }
    final dir = 'assets/dohans/$id';
    final meta = await _bundle.load('$dir/meta.json');
    final lineart = await _bundle.load('$dir/lineart.png');
    final regions = await _bundle.load('$dir/regions.png');

    return DohanPackage.fromBytes(
      // ByteData 는 더 큰 버퍼의 조각일 수 있다. .buffer 를 그대로 쓰면
      // offsetInBytes 를 무시해 엉뚱한 자리에서 읽는다 — Flutter 문서와
      // asset_bundle.dart 내부가 모두 sublistView 를 쓰는 이유다.
      metaJson: utf8.decode(Uint8List.sublistView(meta)),
      lineartPng: Uint8List.sublistView(lineart),
      regionsPng: Uint8List.sublistView(regions),
      label: dir,
    );
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/bundled_dohan_source_test.dart
```

Expected: PASS — 3개 테스트 통과

- [ ] **Step 6: 커밋**

```bash
git add app
git commit -m "feat(app): 에셋에서 내장 도안을 읽는 DohanSource"
```

---

### Task 3: 좌표 변환과 영역 조회

스펙 15장이 "최상" 우선순위로 꼽은 항목이다. 조용히 틀리는 종류이고, 틀리면 아이가 누른 곳과 칠해지는 곳이 어긋난다.

**Files:**
- Create: `app/lib/coloring/canvas_transform.dart`
- Test: `app/test/canvas_transform_test.dart`

**Interfaces:**
- Consumes: `RegionMap`, `kRegionBackground`, `kRegionFirstFillable` (dohan_core)
- Produces: `class CanvasTransform` (필드 `Size viewSize`, `int canvasSize`, `double scale`, `Offset offset`; 생성자 `CanvasTransform.fit(Size viewSize, int canvasSize)`; 메서드 `Offset toCanvas(Offset viewPoint)`, `Offset toView(Offset canvasPoint)`, `Rect get destRect`) · `int regionAt(RegionMap regions, Offset canvasPoint)`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/canvas_transform_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/canvas_transform.dart';

void main() {
  group('CanvasTransform.fit', () {
    test('가로로 넓은 화면에서는 좌우에 여백이 생긴다', () {
      final t = CanvasTransform.fit(const Size(400, 200), 100);

      expect(t.scale, 2.0, reason: '높이 200 / 캔버스 100');
      expect(t.offset, const Offset(100, 0), reason: '(400-200)/2');
    });

    test('세로로 긴 화면에서는 위아래에 여백이 생긴다', () {
      final t = CanvasTransform.fit(const Size(200, 400), 100);

      expect(t.scale, 2.0);
      expect(t.offset, const Offset(0, 100));
    });

    test('정사각 화면은 여백이 없다', () {
      final t = CanvasTransform.fit(const Size(300, 300), 100);

      expect(t.scale, 3.0);
      expect(t.offset, Offset.zero);
    });
  });

  group('좌표 왕복', () {
    test('toCanvas 와 toView 는 서로의 역이다', () {
      final t = CanvasTransform.fit(const Size(400, 200), 100);

      for (final p in [
        const Offset(100, 0),
        const Offset(300, 200),
        const Offset(200, 100),
      ]) {
        final back = t.toView(t.toCanvas(p));
        expect(back.dx, closeTo(p.dx, 1e-9));
        expect(back.dy, closeTo(p.dy, 1e-9));
      }
    });

    test('화면 가운데는 캔버스 가운데다', () {
      final t = CanvasTransform.fit(const Size(400, 200), 100);

      final c = t.toCanvas(const Offset(200, 100));

      expect(c.dx, closeTo(50, 1e-9));
      expect(c.dy, closeTo(50, 1e-9));
    });

    test('destRect 는 여백을 뺀 실제 그림 영역이다', () {
      final t = CanvasTransform.fit(const Size(400, 200), 100);

      expect(t.destRect, const Rect.fromLTWH(100, 0, 200, 200));
    });
  });

  group('regionAt', () {
    RegionMap threeStripes() {
      // 폭 6, 높이 2. 좌/중/우 두 칸씩 ID 2,3,4.
      final ids = Uint16List(12);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 6; x++) {
          ids[y * 6 + x] = 2 + x ~/ 2;
        }
      }
      return RegionMap(6, 2, ids);
    }

    test('캔버스 좌표의 영역 ID 를 읽는다', () {
      final r = threeStripes();

      expect(regionAt(r, const Offset(0.5, 0.5)), 2);
      expect(regionAt(r, const Offset(2.5, 0.5)), 3);
      expect(regionAt(r, const Offset(5.5, 1.5)), 4);
    });

    test('경계 바로 안쪽과 바깥쪽이 다른 영역이다', () {
      final r = threeStripes();

      expect(regionAt(r, const Offset(1.9, 0.5)), 2, reason: '경계 직전');
      expect(regionAt(r, const Offset(2.1, 0.5)), 3, reason: '경계 직후');
    });

    test('캔버스 밖은 배경으로 본다', () {
      final r = threeStripes();

      expect(regionAt(r, const Offset(-1, 0)), kRegionBackground);
      expect(regionAt(r, const Offset(0, -1)), kRegionBackground);
      expect(regionAt(r, const Offset(6, 0)), kRegionBackground);
      expect(regionAt(r, const Offset(0, 2)), kRegionBackground);
    });

    test('오른쪽·아래 끝 픽셀도 읽힌다', () {
      final r = threeStripes();

      expect(regionAt(r, const Offset(5.99, 1.99)), 4);
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/canvas_transform_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/coloring/canvas_transform.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/coloring/canvas_transform.dart`:

```dart
import 'dart:ui';

import 'package:dohan_core/dohan_core.dart';

/// 화면 좌표와 도안 캔버스 좌표 사이의 변환.
///
/// 도안은 항상 정사각형이고, 화면에 비율을 지켜 가운데 맞춤으로 넣는다.
/// 위젯을 모르는 순수 계산이라 화면 없이 테스트할 수 있다 — 아이가 누른 곳과
/// 칠해지는 곳이 어긋나는 것은 조용히 일어나는 종류의 버그라, 이 계산만
/// 따로 잠가 둔다.
class CanvasTransform {
  /// 그릴 수 있는 화면 영역의 크기.
  final Size viewSize;

  /// 도안 캔버스 한 변의 픽셀 수 (보통 1024).
  final int canvasSize;

  /// 캔버스 1픽셀이 화면 몇 픽셀인지.
  final double scale;

  /// 화면에서 도안이 시작하는 왼쪽 위 지점.
  final Offset offset;

  const CanvasTransform({
    required this.viewSize,
    required this.canvasSize,
    required this.scale,
    required this.offset,
  });

  /// 도안을 화면에 비율을 지켜 가운데 맞춤으로 넣는 변환.
  factory CanvasTransform.fit(Size viewSize, int canvasSize) {
    final shortest =
        viewSize.width < viewSize.height ? viewSize.width : viewSize.height;
    final scale = shortest / canvasSize;
    final drawn = canvasSize * scale;
    return CanvasTransform(
      viewSize: viewSize,
      canvasSize: canvasSize,
      scale: scale,
      offset: Offset(
        (viewSize.width - drawn) / 2,
        (viewSize.height - drawn) / 2,
      ),
    );
  }

  /// 화면 좌표를 캔버스 좌표로.
  Offset toCanvas(Offset viewPoint) => Offset(
        (viewPoint.dx - offset.dx) / scale,
        (viewPoint.dy - offset.dy) / scale,
      );

  /// 캔버스 좌표를 화면 좌표로.
  Offset toView(Offset canvasPoint) => Offset(
        canvasPoint.dx * scale + offset.dx,
        canvasPoint.dy * scale + offset.dy,
      );

  /// 화면에서 도안이 실제로 그려지는 사각형.
  Rect get destRect => Rect.fromLTWH(
        offset.dx,
        offset.dy,
        canvasSize * scale,
        canvasSize * scale,
      );
}

/// 캔버스 좌표가 가리키는 영역 ID.
///
/// 캔버스 밖은 [kRegionBackground] 로 본다 — 여백을 눌러도 아무 일이 없어야
/// 한다. 좌표는 내림해서 픽셀을 고른다. 인덱스맵은 데이터이므로 보간하지
/// 않는다.
int regionAt(RegionMap regions, Offset canvasPoint) {
  final x = canvasPoint.dx.floor();
  final y = canvasPoint.dy.floor();
  if (x < 0 || y < 0 || x >= regions.width || y >= regions.height) {
    return kRegionBackground;
  }
  return regions.at(x, y);
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/canvas_transform_test.dart
```

Expected: PASS — 10개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 화면↔캔버스 좌표 변환과 영역 조회"
```

---

### Task 4: 채움 상태와 팔레트 LUT

**Files:**
- Create: `app/lib/coloring/fill_state.dart`
- Test: `app/test/fill_state_test.dart`

**Interfaces:**
- Consumes: `kRegionFirstFillable`, `kMaxRegionId` (dohan_core)
- Produces: `class FillState` (생성자 `FillState()`; 메서드 `void setFill(int regionId, Color? color)`, `Color? fillOf(int regionId)`, `Future<ui.Image> paletteImage()`, `void clear()`, `Map<int, int> toJson()`, `void loadJson(Map<int, int>)`; getter `int filledCount`, `Uint8List lutBytes`)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/fill_state_test.dart`:

```dart
import 'dart:ui';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/fill_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// LUT 에서 영역 ID 의 RGBA 를 읽는다.
  List<int> lutAt(FillState s, int id) {
    final o = ((id >> 8) * 256 + (id & 0xFF)) * 4;
    return [
      s.lutBytes[o],
      s.lutBytes[o + 1],
      s.lutBytes[o + 2],
      s.lutBytes[o + 3],
    ];
  }

  test('처음에는 아무것도 칠해져 있지 않다', () {
    final s = FillState();

    expect(s.filledCount, 0);
    expect(s.fillOf(2), isNull);
    expect(lutAt(s, 2)[3], 0, reason: '알파 0 = 미채색');
  });

  test('영역 ID 를 LUT 좌표 (n%256, n~/256) 에 쓴다', () {
    final s = FillState();

    s.setFill(2, const Color(0xFFEF7586));
    s.setFill(300, const Color(0xFF6CAEE0));

    expect(lutAt(s, 2), [0xEF, 0x75, 0x86, 0xFF]);
    expect(lutAt(s, 300), [0x6C, 0xAE, 0xE0, 0xFF],
        reason: '상위 바이트가 있는 ID 도 제자리에 들어가야 한다');
  });

  test('null 을 주면 미채색으로 되돌린다', () {
    final s = FillState()..setFill(2, const Color(0xFFEF7586));

    s.setFill(2, null);

    expect(s.fillOf(2), isNull);
    expect(s.filledCount, 0);
    expect(lutAt(s, 2)[3], 0);
  });

  test('선(0)과 배경(1)은 칠할 수 없다', () {
    final s = FillState();

    expect(() => s.setFill(kRegionLine, const Color(0xFFFF0000)),
        throwsA(isA<ArgumentError>()));
    expect(() => s.setFill(kRegionBackground, const Color(0xFFFF0000)),
        throwsA(isA<ArgumentError>()));
  });

  test('JSON 으로 왕복한다', () {
    final s = FillState()
      ..setFill(2, const Color(0xFFEF7586))
      ..setFill(300, const Color(0xFF6CAEE0));

    final restored = FillState()..loadJson(s.toJson());

    expect(restored.fillOf(2), const Color(0xFFEF7586));
    expect(restored.fillOf(300), const Color(0xFF6CAEE0));
    expect(restored.filledCount, 2);
    expect(lutAt(restored, 300), [0x6C, 0xAE, 0xE0, 0xFF]);
  });

  test('팔레트 이미지는 256x256 이다', () async {
    final s = FillState()..setFill(2, const Color(0xFFEF7586));

    final im = await s.paletteImage();

    expect(im.width, 256);
    expect(im.height, 256);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/fill_state_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/coloring/fill_state.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/coloring/fill_state.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/painting.dart' show Color;

/// 어느 영역이 무슨 색인지, 그리고 그것을 셰이더가 읽을 팔레트 텍스처로
/// 옮기는 일까지 맡는다.
///
/// 팔레트는 256×256 RGBA 다. 영역 ID `n` 은 좌표 `(n % 256, n ~/ 256)` 에
/// 놓이므로, 셰이더는 ID 의 하위·상위 바이트를 그대로 좌표로 쓸 수 있다.
/// 알파 0 은 "아직 칠하지 않음" 을 뜻한다.
class FillState {
  static const _side = 256;

  final Map<int, Color> _fills = {};
  final Uint8List _lut = Uint8List(_side * _side * 4);

  /// 팔레트 텍스처의 원본 바이트. 테스트와 디버깅용이다.
  Uint8List get lutBytes => _lut;

  int get filledCount => _fills.length;

  Color? fillOf(int regionId) => _fills[regionId];

  /// 영역 하나의 색을 정한다. [color] 가 null 이면 미채색으로 되돌린다.
  void setFill(int regionId, Color? color) {
    if (regionId < kRegionFirstFillable) {
      throw ArgumentError(
          '선(0)과 배경(1)은 칠할 수 없습니다: $regionId');
    }
    if (regionId > kMaxRegionId) {
      throw ArgumentError('영역 ID 범위를 벗어났습니다: $regionId');
    }

    final o = ((regionId >> 8) * _side + (regionId & 0xFF)) * 4;
    if (color == null) {
      _fills.remove(regionId);
      _lut[o] = 0;
      _lut[o + 1] = 0;
      _lut[o + 2] = 0;
      _lut[o + 3] = 0;
      return;
    }

    _fills[regionId] = color;
    _lut[o] = (color.r * 255).round();
    _lut[o + 1] = (color.g * 255).round();
    _lut[o + 2] = (color.b * 255).round();
    _lut[o + 3] = (color.a * 255).round();
  }

  void clear() {
    _fills.clear();
    _lut.fillRange(0, _lut.length, 0);
  }

  /// 영역 ID → ARGB 정수. 작품 파일에 그대로 넣는다.
  Map<int, int> toJson() =>
      {for (final e in _fills.entries) e.key: e.value.toARGB32()};

  void loadJson(Map<int, int> json) {
    clear();
    json.forEach((id, argb) => setFill(id, Color(argb)));
  }

  /// 셰이더에 넘길 팔레트 텍스처.
  ///
  /// 256×256 한 장을 만드는 데 0.2ms 정도다. 탭마다 새로 만들어도 한 프레임
  /// 안에 충분히 들어간다.
  Future<ui.Image> paletteImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _lut,
      _side,
      _side,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/fill_state_test.dart
```

Expected: PASS — 6개 테스트 통과

`Color.r`/`.g`/`.b`/`.a` 는 0.0~1.0 double 이고 `toARGB32()` 는 Flutter 3.27 이후의 API다. 3.47.5에서 정상이다. 분석기가 `withOpacity` 같은 옛 API를 권하면 무시한다.

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 채움 상태와 팔레트 LUT"
```

---

### Task 5: 채움 셰이더와 페인터

**Files:**
- Create: `app/shaders/fill.frag`
- Create: `app/lib/coloring/coloring_painter.dart`
- Test: `app/test/fill_shader_test.dart`

**Interfaces:**
- Consumes: `FillState` (Task 4), `CanvasTransform` (Task 3), `RegionMap` (dohan_core)
- Produces: `shaders/fill.frag` · `class ColoringPainter extends CustomPainter` (생성자 `ColoringPainter({required ui.FragmentShader shader, required ui.Image regions, required ui.Image palette, required ui.Image lineart, required int canvasSize})`)

**셰이더 uniform 순서는 바꾸지 말 것.** `setFloat` 인덱스는 선언 순서를 따른다: 0=uSize.x, 1=uSize.y, 2=uMapSize.x, 3=uMapSize.y. 샘플러는 별도 인덱스로 0=uRegions, 1=uPalette.

- [ ] **Step 1: 셰이더 작성**

`app/shaders/fill.frag` — 아래 코드는 Flutter 3.47.5에서 실측으로 통과한 것이다. 그대로 옮긴다.

```glsl
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // 이 셰이더가 채우는 사각형의 크기 (캔버스 논리 단위)
uniform vec2 uMapSize;   // 인덱스맵 크기 (픽셀)
uniform sampler2D uRegions;
uniform sampler2D uPalette;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // 텍셀 중심으로 스냅한다. 샘플러가 선형 보간이어도 정확히 그 텍셀 값이
  // 나오므로 필터 모드와 무관하게 영역 ID 가 섞이지 않는다. 측정해 보면
  // 지금 Flutter 는 nearest 지만, 백엔드나 버전에 따라 달라질 수 있고
  // 어긋나면 조용히 엉뚱한 칸이 칠해진다.
  vec2 snapped = (floor(uv * uMapSize) + 0.5) / uMapSize;
  vec4 r = texture(uRegions, snapped);

  float lo = floor(r.r * 255.0 + 0.5);
  float hi = floor(r.g * 255.0 + 0.5);
  float id = lo + hi * 256.0;

  // 0 = 선, 1 = 배경. 둘 다 채움 레이어에서는 투명하다.
  if (id < 2.0) {
    fragColor = vec4(0.0);
    return;
  }

  // 팔레트는 256x256. ID n 은 (n%256, n/256) 에 놓이므로 lo, hi 가 곧 좌표다.
  vec4 c = texture(uPalette, (vec2(lo, hi) + 0.5) / 256.0);

  // Flutter 셰이더 출력은 미리 곱해진 알파다.
  fragColor = vec4(c.rgb * c.a, c.a);
}
```

- [ ] **Step 2: pubspec 에 셰이더 등록**

`app/pubspec.yaml` 의 `flutter:` 절에 추가한다. `assets:` 아래, 같은 들여쓰기다.

```yaml
  shaders:
    - shaders/fill.frag
```

Task 1 에서 일부러 미뤄 둔 등록이다 — 파일과 등록이 한 태스크 안에 같이 있어야 그 시점의 `flutter test` 가 통과한다.

- [ ] **Step 3: 실패하는 테스트 작성**

`app/test/fill_shader_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/coloring_painter.dart';
import 'package:kkumul/coloring/fill_state.dart';

Future<ui.Image> _rgba(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 영역 ID 를 R/G 에 인코딩한 가로 줄 인덱스맵.
Future<ui.Image> _regionStrip(List<int> ids) {
  final px = Uint8List(ids.length * 4);
  for (var i = 0; i < ids.length; i++) {
    px[i * 4] = ids[i] & 0xFF;
    px[i * 4 + 1] = (ids[i] >> 8) & 0xFF;
    px[i * 4 + 3] = 255;
  }
  return _rgba(px, ids.length, 1);
}

Future<ui.Image> _transparent(int w, int h) =>
    _rgba(Uint8List(w * h * 4), w, h);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('셰이더가 ID 를 디코딩하고 팔레트에서 색을 찾는다', () async {
    const ids = [0, 1, 2, 3, 300];
    final regions = await _regionStrip(ids);
    final lineart = await _transparent(ids.length, 1);

    final fills = FillState()
      ..setFill(2, const Color(0xFFFF0000))
      ..setFill(300, const Color(0xFF0000FF));
    // ID 3 은 일부러 비워 둔다 = 미채색
    final palette = await fills.paletteImage();

    final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
    final painter = ColoringPainter(
      shader: program.fragmentShader(),
      regions: regions,
      palette: palette,
      lineart: lineart,
      canvasSize: ids.length,
    );

    final rec = ui.PictureRecorder();
    painter.paint(ui.Canvas(rec), ui.Size(ids.length.toDouble(), 1));
    final out = await rec.endRecording().toImage(ids.length, 1);
    final d = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    List<int> at(int x) => [
          d.getUint8(x * 4),
          d.getUint8(x * 4 + 1),
          d.getUint8(x * 4 + 2),
          d.getUint8(x * 4 + 3),
        ];

    expect(at(0), [255, 255, 255, 255], reason: '선 자리도 흰 배경이 비친다');
    expect(at(1), [255, 255, 255, 255], reason: '배경 자리도 흰 배경');
    expect(at(2), [255, 0, 0, 255], reason: 'ID 2 는 빨강');
    expect(at(3), [255, 255, 255, 255], reason: '미채색은 흰 배경이 비친다');
    expect(at(4), [0, 0, 255, 255], reason: 'ID 300 — 상위 바이트 경로');
  });

  test('칠하지 않은 도안은 전부 흰 배경이다', () async {
    const ids = [2, 3, 4, 5];
    final regions = await _regionStrip(ids);
    final lineart = await _transparent(ids.length, 1);
    final palette = await FillState().paletteImage();

    final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
    final rec = ui.PictureRecorder();
    ColoringPainter(
      shader: program.fragmentShader(),
      regions: regions,
      palette: palette,
      lineart: lineart,
      canvasSize: ids.length,
    ).paint(ui.Canvas(rec), ui.Size(ids.length.toDouble(), 1));

    final out = await rec.endRecording().toImage(ids.length, 1);
    final d = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    for (var x = 0; x < ids.length; x++) {
      expect(d.getUint8(x * 4 + 3), 255);
      expect(d.getUint8(x * 4), 255, reason: '$x 번 픽셀이 흰색이어야 한다');
    }
  });
}
```

`Size` 를 `ui.Size` 로 한정한 이유는, 이 파일이 `dart:ui` 를 `as ui` 로 들여오고 `flutter_test` 는 `Size` 를 이름 그대로 내보내지 않기 때문이다. 한정 없이 쓰면 컴파일되지 않는다.

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd app && flutter test test/fill_shader_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/coloring/coloring_painter.dart'`

- [ ] **Step 5: 페인터 작성**

`app/lib/coloring/coloring_painter.dart`:

```dart
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// 도안 한 장을 그린다.
///
/// 아래에서 위로: 흰 배경 → 채움(셰이더) → 선화. 브러시와 스티커 층은
/// 계획 3 이 이 사이에 끼워 넣는다.
///
/// 좌표계는 도안의 논리 캔버스([canvasSize] × [canvasSize])다. 화면에 맞추는
/// 확대·이동은 호출하는 쪽이 캔버스 변환으로 건다 — `FlutterFragCoord()` 가
/// 로컬 좌표라 셰이더는 변환을 그대로 따라간다.
class ColoringPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image regions;
  final ui.Image palette;
  final ui.Image lineart;
  final int canvasSize;

  ColoringPainter({
    required this.shader,
    required this.regions,
    required this.palette,
    required this.lineart,
    required this.canvasSize,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final rect = ui.Rect.fromLTWH(
      0,
      0,
      canvasSize.toDouble(),
      canvasSize.toDouble(),
    );

    // 1) 흰 배경
    canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFFFFFFF));

    // 2) 채움 레이어
    shader
      ..setFloat(0, canvasSize.toDouble())
      ..setFloat(1, canvasSize.toDouble())
      ..setFloat(2, regions.width.toDouble())
      ..setFloat(3, regions.height.toDouble())
      ..setImageSampler(0, regions)
      ..setImageSampler(1, palette);
    canvas.drawRect(rect, ui.Paint()..shader = shader);

    // 3) 선화
    canvas.drawImageRect(
      lineart,
      ui.Rect.fromLTWH(
        0,
        0,
        lineart.width.toDouble(),
        lineart.height.toDouble(),
      ),
      rect,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(ColoringPainter old) =>
      old.palette != palette ||
      old.regions != regions ||
      old.lineart != lineart ||
      old.canvasSize != canvasSize;
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd app && flutter test test/fill_shader_test.dart
```

Expected: PASS — 2개 테스트 통과

- [ ] **Step 7: 커밋**

```bash
git add app
git commit -m "feat(app): 채움 셰이더와 도안 페인터"
```

---

### Task 6: 되돌리기 스택

**Files:**
- Create: `app/lib/core/command.dart`
- Test: `app/test/command_test.dart`

**Interfaces:**
- Consumes: `FillState` (Task 4)
- Produces: `abstract class Command` (메서드 `void apply(FillState)`, `void revert(FillState)`) · `class FillCommand implements Command` (생성자 `FillCommand({required int regionId, required Color? before, required Color? after})`) · `class UndoStack` (생성자 `UndoStack({int depth = 50})`; 메서드 `void push(Command, FillState)`, `bool undo(FillState)`, `void clear()`; getter `bool canUndo`, `int length`)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/command_test.dart`:

```dart
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/fill_state.dart';
import 'package:kkumul/core/command.dart';

void main() {
  const red = Color(0xFFFF0000);
  const blue = Color(0xFF0000FF);

  test('칠하기를 되돌리면 이전 색으로 돌아간다', () {
    final fills = FillState();
    final stack = UndoStack();

    stack.push(
        FillCommand(regionId: 2, before: null, after: red), fills);
    expect(fills.fillOf(2), red);

    expect(stack.undo(fills), isTrue);
    expect(fills.fillOf(2), isNull);
  });

  test('덧칠을 되돌리면 그 전 색으로 돌아간다', () {
    final fills = FillState();
    final stack = UndoStack();

    stack.push(FillCommand(regionId: 2, before: null, after: red), fills);
    stack.push(FillCommand(regionId: 2, before: red, after: blue), fills);
    expect(fills.fillOf(2), blue);

    stack.undo(fills);
    expect(fills.fillOf(2), red, reason: '한 단계만 되돌린다');

    stack.undo(fills);
    expect(fills.fillOf(2), isNull);
  });

  test('되돌릴 것이 없으면 false 를 돌려준다', () {
    expect(UndoStack().undo(FillState()), isFalse);
    expect(UndoStack().canUndo, isFalse);
  });

  test('여러 영역을 섞어 칠해도 순서대로 되돌아간다', () {
    final fills = FillState();
    final stack = UndoStack();

    stack.push(FillCommand(regionId: 2, before: null, after: red), fills);
    stack.push(FillCommand(regionId: 3, before: null, after: blue), fills);
    stack.push(FillCommand(regionId: 2, before: red, after: blue), fills);

    stack.undo(fills);
    expect(fills.fillOf(2), red);
    expect(fills.fillOf(3), blue);

    stack.undo(fills);
    expect(fills.fillOf(3), isNull);

    stack.undo(fills);
    expect(fills.fillOf(2), isNull);
    expect(stack.canUndo, isFalse);
  });

  test('스택 깊이를 넘으면 가장 오래된 것부터 버린다', () {
    final fills = FillState();
    final stack = UndoStack(depth: 3);

    for (var i = 0; i < 5; i++) {
      stack.push(
          FillCommand(regionId: 2 + i, before: null, after: red), fills);
    }

    expect(stack.length, 3);
    while (stack.canUndo) {
      stack.undo(fills);
    }
    // 버려진 두 개는 되돌릴 수 없으므로 칠해진 채로 남는다.
    expect(fills.fillOf(2), red);
    expect(fills.fillOf(3), red);
    expect(fills.fillOf(4), isNull);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/command_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/core/command.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/core/command.dart`:

```dart
import 'dart:collection';

import 'package:flutter/painting.dart' show Color;

import '../coloring/fill_state.dart';

/// 되돌릴 수 있는 한 번의 조작.
abstract class Command {
  void apply(FillState fills);
  void revert(FillState fills);
}

/// 영역 하나의 색을 바꾼 일.
///
/// 이전 색과 새 색만 들고 있으면 되므로 수십 바이트다. 레이어를 통째로
/// 스냅샷하는 것과 비교가 되지 않는다.
class FillCommand implements Command {
  final int regionId;
  final Color? before;
  final Color? after;

  const FillCommand({
    required this.regionId,
    required this.before,
    required this.after,
  });

  @override
  void apply(FillState fills) => fills.setFill(regionId, after);

  @override
  void revert(FillState fills) => fills.setFill(regionId, before);
}

/// 되돌리기 스택.
///
/// 다시 실행(redo)은 두지 않는다. 기획서의 연령대에서 되돌리기는 "실수를 쉽게
/// 지우는" 장치이지 편집 히스토리가 아니고, redo 버튼이 하나 더 늘면 도구바가
/// 그만큼 복잡해진다.
class UndoStack {
  final int depth;
  final Queue<Command> _stack = Queue<Command>();

  UndoStack({this.depth = 50});

  bool get canUndo => _stack.isNotEmpty;

  int get length => _stack.length;

  /// 명령을 적용하고 스택에 쌓는다.
  void push(Command command, FillState fills) {
    command.apply(fills);
    _stack.addLast(command);
    while (_stack.length > depth) {
      _stack.removeFirst();
    }
  }

  /// 마지막 명령을 되돌린다. 되돌릴 것이 없으면 false.
  bool undo(FillState fills) {
    if (_stack.isEmpty) return false;
    _stack.removeLast().revert(fills);
    return true;
  }

  void clear() => _stack.clear();
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/command_test.dart
```

Expected: PASS — 5개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 되돌리기 명령 스택"
```

---

### Task 7: 작품 저장소

**Files:**
- Create: `app/lib/core/artwork.dart`
- Create: `app/lib/gallery/artwork_repository.dart`
- Test: `app/test/artwork_repository_test.dart`

**Interfaces:**
- Consumes: `FillState` (Task 4)
- Produces: `class Artwork` (필드 `String id`, `String dohanId`, `Map<int,int> fills`, `DateTime updatedAt`; `Map<String,dynamic> toJson()`, `factory Artwork.fromJson(Map<String,dynamic>)`) · `class ArtworkRepository` (생성자 `ArtworkRepository(Directory root)`; 메서드 `Future<void> save(Artwork)`, `Future<Artwork?> load(String id)`, `Future<List<Artwork>> listAll()`, `Future<void> delete(String id)`)

작품 하나는 폴더 하나다. 중앙 인덱스 파일을 두지 않는다 — 인덱스 하나가 깨지면 아이의 작품 전체가 한 번에 사라지기 때문이다. 목록은 디렉터리를 훑어 만든다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/artwork_repository_test.dart`:

```dart
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
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/artwork_repository_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/core/artwork.dart'`

- [ ] **Step 3: 모델 작성**

`app/lib/core/artwork.dart`:

```dart
/// 아이가 칠하고 있는 작품 하나.
///
/// 1단계에서는 채움 색만 담는다. 브러시 레이어와 스티커는 계획 3 이 같은
/// 폴더에 파일을 더 넣는 식으로 붙인다.
class Artwork {
  final String id;
  final String dohanId;

  /// 영역 ID → ARGB 정수.
  final Map<int, int> fills;

  final DateTime updatedAt;

  const Artwork({
    required this.id,
    required this.dohanId,
    required this.fills,
    required this.updatedAt,
  });

  Artwork copyWith({Map<int, int>? fills, DateTime? updatedAt}) => Artwork(
        id: id,
        dohanId: dohanId,
        fills: fills ?? this.fills,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'dohanId': dohanId,
        'fills': {for (final e in fills.entries) e.key.toString(): e.value},
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Artwork.fromJson(Map<String, dynamic> json) => Artwork(
        id: json['id'] as String,
        dohanId: json['dohanId'] as String,
        fills: {
          for (final e in (json['fills'] as Map).entries)
            int.parse(e.key as String): e.value as int
        },
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
```

- [ ] **Step 4: 저장소 작성**

`app/lib/gallery/artwork_repository.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import '../core/artwork.dart';

/// 작품을 폴더 단위로 저장한다.
///
/// 작품 하나 = 폴더 하나이고, 목록은 디렉터리를 훑어 만든다. 중앙 인덱스
/// 파일을 두지 않는 것은 의도된 선택이다 — 인덱스가 하나 있으면 그것이
/// 깨졌을 때 아이의 작품 전체가 한 번에 사라진다. 폴더 하나가 손상돼도
/// 나머지는 멀쩡하다.
class ArtworkRepository {
  final Directory root;

  ArtworkRepository(this.root);

  Directory get _artworksDir => Directory('${root.path}/artworks');

  Directory _dirFor(String id) => Directory('${_artworksDir.path}/$id');

  File _fileFor(String id) => File('${_dirFor(id).path}/artwork.json');

  /// 작품을 쓴다. 임시 파일에 쓰고 rename 해서, 쓰는 도중 앱이 죽어도
  /// 반쯤 쓰인 파일이 남지 않게 한다.
  Future<void> save(Artwork artwork) async {
    final dir = _dirFor(artwork.id);
    await dir.create(recursive: true);

    final tmp = File('${dir.path}/artwork.json.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(artwork.toJson()),
      flush: true,
    );
    await tmp.rename(_fileFor(artwork.id).path);
  }

  Future<Artwork?> load(String id) async {
    final file = _fileFor(id);
    if (!file.existsSync()) return null;
    try {
      return Artwork.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      // 손상된 폴더 하나 때문에 나머지를 못 읽게 하지 않는다.
      return null;
    }
  }

  /// 최근에 고친 것부터.
  Future<List<Artwork>> listAll() async {
    if (!_artworksDir.existsSync()) return const [];
    final out = <Artwork>[];
    for (final entity in _artworksDir.listSync()) {
      if (entity is! Directory) continue;
      final artwork = await load(entity.path.split(Platform.pathSeparator).last);
      if (artwork != null) out.add(artwork);
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> delete(String id) async {
    final dir = _dirFor(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/artwork_repository_test.dart
```

Expected: PASS — 7개 테스트 통과

- [ ] **Step 6: 커밋**

```bash
git add app
git commit -m "feat(app): 폴더 단위 작품 저장소"
```

---

### Task 8: 자동 저장

**Files:**
- Create: `app/lib/gallery/autosave.dart`
- Test: `app/test/autosave_test.dart`

**Interfaces:**
- Consumes: `Artwork` (Task 7), `ArtworkRepository` (Task 7)
- Produces: `class Autosave` (생성자 `Autosave({required ArtworkRepository repository, Duration debounce = const Duration(seconds: 1)})`; 메서드 `void schedule(Artwork)`, `Future<void> flush()`, `void dispose()`; getter `int saveCount`)

아이는 저장 버튼을 누르지 않는다. 조작이 있을 때마다 예약하고 1초 뒤에 쓴다. 앱이 백그라운드로 가면 기다리지 않고 바로 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/autosave_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/gallery/autosave.dart';

void main() {
  late Directory root;
  late ArtworkRepository repo;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_auto_');
    repo = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Artwork art(int color) => Artwork(
        id: 'a1',
        dohanId: 'flower-01',
        fills: {2: color},
        updatedAt: DateTime.utc(2026, 9, 25),
      );

  test('연달아 예약하면 마지막 것 한 번만 쓴다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(milliseconds: 40),
    );
    addTearDown(auto.dispose);

    auto.schedule(art(0xFF111111));
    auto.schedule(art(0xFF222222));
    auto.schedule(art(0xFF333333));

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(auto.saveCount, 1, reason: '디바운스로 한 번만 써야 한다');
    expect((await repo.load('a1'))!.fills[2], 0xFF333333);
  });

  test('flush 는 기다리지 않고 바로 쓴다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    auto.schedule(art(0xFF444444));
    await auto.flush();

    expect(auto.saveCount, 1);
    expect((await repo.load('a1'))!.fills[2], 0xFF444444);
  });

  test('예약한 것이 없으면 flush 가 아무것도 쓰지 않는다', () async {
    final auto = Autosave(repository: repo);
    addTearDown(auto.dispose);

    await auto.flush();

    expect(auto.saveCount, 0);
  });

  test('dispose 후에는 예약해도 쓰지 않는다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(milliseconds: 20),
    );

    auto.dispose();
    auto.schedule(art(0xFF555555));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(auto.saveCount, 0);
    expect(await repo.load('a1'), isNull);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/autosave_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/gallery/autosave.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/gallery/autosave.dart`:

```dart
import 'dart:async';

import '../core/artwork.dart';
import 'artwork_repository.dart';

/// 조작이 멈추면 알아서 저장한다.
///
/// 아이는 저장 버튼을 누르지 않는다. 탭 한 번마다 파일을 쓰면 낭비이고,
/// 안 쓰면 앱이 죽었을 때 그림이 날아간다. 마지막 조작에서 [debounce] 만큼
/// 지나면 한 번 쓴다. 앱이 백그라운드로 갈 때는 [flush] 로 즉시 쓴다.
class Autosave {
  final ArtworkRepository repository;
  final Duration debounce;

  Timer? _timer;
  Artwork? _pending;
  bool _disposed = false;
  int _saveCount = 0;

  Autosave({
    required this.repository,
    this.debounce = const Duration(seconds: 1),
  });

  /// 지금까지 실제로 파일을 쓴 횟수. 디바운스가 동작하는지 확인하는 용도다.
  int get saveCount => _saveCount;

  void schedule(Artwork artwork) {
    if (_disposed) return;
    _pending = artwork;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush());
    });
  }

  /// 예약된 것이 있으면 기다리지 않고 지금 쓴다.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final artwork = _pending;
    if (artwork == null) return;
    _pending = null;
    await repository.save(artwork);
    _saveCount++;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/autosave_test.dart
```

Expected: PASS — 4개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 디바운스 자동 저장"
```

---

### Task 9: 색칠 컨트롤러

지금까지 만든 조각을 하나로 묶는다. 위젯을 모르는 순수 상태 객체라 화면 없이 테스트할 수 있다.

**Files:**
- Create: `app/lib/coloring/coloring_controller.dart`
- Test: `app/test/coloring_controller_test.dart`

**Interfaces:**
- Consumes: `DohanSource` (Task 2), `CanvasTransform`·`regionAt` (Task 3), `FillState` (Task 4), `UndoStack`·`FillCommand` (Task 6), `Artwork` (Task 7), `Autosave` (Task 8)
- Produces: `class ColoringController extends ChangeNotifier` (생성자 `ColoringController({required DohanSource source, required Autosave autosave})`; 메서드 `Future<void> open({required String dohanId, required String artworkId, Artwork? existing})`, `bool tapAt(Offset canvasPoint)`, `bool undo()`, `void pickColor(Color)`, `Future<void> close()`; getter `DohanPackage? dohan`, `FillState fills`, `Color selectedColor`, `bool canUndo`, `bool isReady`)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/coloring_controller_test.dart`:

```dart
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
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/coloring_controller_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/coloring/coloring_controller.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/coloring/coloring_controller.dart`:

```dart
import 'dart:ui' show Offset;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../core/artwork.dart';
import '../core/command.dart';
import '../core/dohan_source.dart';
import '../gallery/autosave.dart';
import 'canvas_transform.dart';
import 'fill_state.dart';

/// 색칠 화면의 상태를 한곳에 묶는다.
///
/// 위젯을 모른다 — 탭 좌표는 이미 캔버스 좌표로 바뀐 것을 받는다. 화면 없이
/// 테스트할 수 있어야 색칠 규칙을 위젯 테스트의 복잡도 없이 잠글 수 있다.
class ColoringController extends ChangeNotifier {
  final DohanSource source;
  final Autosave autosave;

  ColoringController({required this.source, required this.autosave});

  DohanPackage? _dohan;
  String? _artworkId;
  final FillState _fills = FillState();
  final UndoStack _undo = UndoStack();
  Color _selected = const Color(0xFFEF7586);

  DohanPackage? get dohan => _dohan;
  FillState get fills => _fills;
  Color get selectedColor => _selected;
  bool get canUndo => _undo.canUndo;
  bool get isReady => _dohan != null;

  /// 도안을 열고, 이어 그리던 작품이 있으면 그 상태를 얹는다.
  Future<void> open({
    required String dohanId,
    required String artworkId,
    Artwork? existing,
  }) async {
    _dohan = await source.load(dohanId);
    _artworkId = artworkId;
    _undo.clear();
    _fills.clear();
    if (existing != null) _fills.loadJson(existing.fills);
    notifyListeners();
  }

  void pickColor(Color color) {
    _selected = color;
    notifyListeners();
  }

  /// 캔버스 좌표를 칠한다. 실제로 바뀐 것이 있으면 true.
  bool tapAt(Offset canvasPoint) {
    final dohan = _dohan;
    if (dohan == null) return false;

    final id = regionAt(dohan.regions, canvasPoint);
    if (id < kRegionFirstFillable) return false;

    final before = _fills.fillOf(id);
    if (before == _selected) return false;

    _undo.push(
      FillCommand(regionId: id, before: before, after: _selected),
      _fills,
    );
    _scheduleSave();
    notifyListeners();
    return true;
  }

  bool undo() {
    if (!_undo.undo(_fills)) return false;
    _scheduleSave();
    notifyListeners();
    return true;
  }

  /// 화면을 떠나기 전에 예약된 저장을 마무리한다.
  Future<void> close() async {
    await autosave.flush();
  }

  void _scheduleSave() {
    final dohan = _dohan;
    final id = _artworkId;
    if (dohan == null || id == null) return;
    autosave.schedule(Artwork(
      id: id,
      dohanId: dohan.meta.id,
      fills: _fills.toJson(),
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  @override
  void dispose() {
    autosave.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/coloring_controller_test.dart
```

Expected: PASS — 8개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 색칠 컨트롤러"
```

---

### Task 10: 색칠 화면

**Files:**
- Create: `app/lib/ui/palette_bar.dart`
- Create: `app/lib/ui/coloring_screen.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/coloring_screen_test.dart`

**Interfaces:**
- Consumes: `ColoringController` (Task 9), `ColoringPainter` (Task 5), `CanvasTransform` (Task 3), `BundledDohanSource` (Task 2), `ArtworkRepository`·`Autosave` (Task 7·8)
- Produces: `class PaletteBar extends StatelessWidget` (생성자 `PaletteBar({required List<Color> colors, required Color selected, required ValueChanged<Color> onPick})`) · `class ColoringScreen extends StatefulWidget` (생성자 `ColoringScreen({required ColoringController controller})`)

기본 팔레트 8색은 스펙 9장의 값을 그대로 쓴다. 터치 타겟은 64dp 이상이다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/coloring_screen_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_controller.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/gallery/autosave.dart';
import 'package:kkumul/ui/coloring_screen.dart';
import 'package:kkumul/ui/palette_bar.dart';

class FakeDohanSource implements DohanSource {
  @override
  Future<List<String>> listIds() async => ['fake'];

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
        createdAt: DateTime.utc(2026, 9, 25),
      ),
      lineart: img.Image(width: n, height: n, numChannels: 4),
      regions: RegionMap(n, n, ids),
    );
  }
}

void main() {
  late Directory root;
  late ColoringController controller;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('kkumul_ui_');
    controller = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(
        repository: ArtworkRepository(root),
        // 기본 1초를 쓰면 탭하는 테스트가 끝난 뒤에도 타이머가 살아 있어
        // flutter_test 가 "A Timer is still pending" 으로 실패한다.
        debounce: const Duration(milliseconds: 20),
      ),
    );
    await controller.open(dohanId: 'fake', artworkId: 'w1');
  });
  tearDown(() async {
    await controller.close();
    controller.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('팔레트에서 색을 고르면 컨트롤러에 반영된다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final swatches = find.byType(ColorSwatchButton);
    expect(swatches, findsNWidgets(8), reason: '유아 팔레트는 8색이다');

    await tester.tap(swatches.at(4));
    await tester.pump();

    expect(controller.selectedColor, PaletteBar.toddlerPalette[4]);
  });

  testWidgets('캔버스를 탭하면 그 영역이 칠해진다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final canvas = find.byKey(const ValueKey('coloring-canvas'));
    final box = tester.getRect(canvas);

    // 왼쪽 절반 = 영역 2
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();

    expect(controller.fills.fillOf(2), isNotNull);
    expect(controller.fills.fillOf(3), isNull);
  });

  testWidgets('되돌리기 버튼은 되돌릴 것이 있을 때만 눌린다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final undo = find.byKey(const ValueKey('undo-button'));
    expect(tester.widget<IconButton>(undo).onPressed, isNull,
        reason: '처음에는 되돌릴 것이 없다');

    final box = tester.getRect(find.byKey(const ValueKey('coloring-canvas')));
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();

    expect(tester.widget<IconButton>(undo).onPressed, isNotNull);

    await tester.tap(undo);
    await tester.pump();

    expect(controller.fills.filledCount, 0);
  });

  testWidgets('터치 타겟이 64dp 이상이다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    for (final e in find.byType(ColorSwatchButton).evaluate()) {
      final size = tester.getSize(find.byWidget(e.widget));
      expect(size.width, greaterThanOrEqualTo(64));
      expect(size.height, greaterThanOrEqualTo(64));
    }
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/coloring_screen_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/ui/coloring_screen.dart'`

- [ ] **Step 3: 팔레트 위젯 작성**

`app/lib/ui/palette_bar.dart`:

```dart
import 'package:flutter/material.dart';

/// 색 하나를 고르는 동그란 버튼.
///
/// 터치 타겟을 64dp 로 잡는다 — 스펙 10.3 절의 최소값이고, 아이 손가락은
/// 어른보다 부정확하다.
class ColorSwatchButton extends StatelessWidget {
  static const double size = 64;

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? const Color(0xFF202923) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 색 고르는 줄.
class PaletteBar extends StatelessWidget {
  /// 스펙 9장의 유아 기본 팔레트 8색.
  static const toddlerPalette = <Color>[
    Color(0xFFEF7586), // 분홍
    Color(0xFFF1BD45), // 노랑
    Color(0xFFEF8A45), // 주황
    Color(0xFF6CAEE0), // 파랑
    Color(0xFF63B98B), // 초록
    Color(0xFF9E82CF), // 보라
    Color(0xFF795548), // 갈색
    Color(0xFFF5F5F5), // 흰색
  ];

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onPick;

  const PaletteBar({
    super.key,
    required this.colors,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ColorSwatchButton.size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in colors)
            ColorSwatchButton(
              color: c,
              selected: c.toARGB32() == selected.toARGB32(),
              onTap: () => onPick(c),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 화면 작성**

`app/lib/ui/coloring_screen.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../coloring/canvas_transform.dart';
import '../coloring/coloring_controller.dart';
import '../coloring/coloring_painter.dart';
import 'palette_bar.dart';

/// 도안 하나를 칠하는 화면.
class ColoringScreen extends StatefulWidget {
  final ColoringController controller;

  const ColoringScreen({super.key, required this.controller});

  @override
  State<ColoringScreen> createState() => _ColoringScreenState();
}

class _ColoringScreenState extends State<ColoringScreen>
    with WidgetsBindingObserver {
  ui.FragmentShader? _shader;
  ui.Image? _regionsImage;
  ui.Image? _lineartImage;
  ui.Image? _paletteImage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onChanged);
    unawaited(_prepare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 물러날 때는 디바운스를 기다리지 않고 바로 쓴다.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(widget.controller.close());
    }
  }

  /// 팔레트 갱신이 겹쳤을 때 늦게 시작한 것이 이기도록 세대 번호를 둔다.
  int _paletteGeneration = 0;

  void _onChanged() {
    unawaited(_refreshPalette());
  }

  Future<void> _prepare() async {
    final dohan = widget.controller.dohan;
    if (dohan == null) return;

    final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
    final regions = await _regionsToImage(dohan.regions);
    final lineart = await _decode(
        Uint8List.fromList(img.encodePng(dohan.lineart)));
    final palette = await widget.controller.fills.paletteImage();

    if (!mounted) return;
    setState(() {
      _shader = program.fragmentShader();
      _regionsImage = regions;
      _lineartImage = lineart;
      _paletteImage = palette;
    });
  }

  Future<void> _refreshPalette() async {
    final generation = ++_paletteGeneration;
    final palette = await widget.controller.fills.paletteImage();
    // 빠르게 연달아 탭하면 이미지 생성이 겹친다. 늦게 시작한 쪽이 최신이므로
    // 그 사이 세대가 올라갔으면 이 결과는 버린다.
    if (!mounted || generation != _paletteGeneration) return;
    setState(() => _paletteImage = palette);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = _shader != null &&
        _regionsImage != null &&
        _lineartImage != null &&
        _paletteImage != null &&
        c.dohan != null;

    return Scaffold(
      backgroundColor: const Color(0xFFFCFCF8),
      appBar: AppBar(
        title: Text(c.dohan?.meta.title ?? '색칠하기'),
        actions: [
          IconButton(
            key: const ValueKey('undo-button'),
            icon: const Icon(Icons.undo),
            tooltip: '되돌리기',
            iconSize: 32,
            onPressed: c.canUndo
                ? () {
                    c.undo();
                  }
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ready
                ? _buildCanvas(c)
                : const Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: PaletteBar(
              colors: PaletteBar.toddlerPalette,
              selected: c.selectedColor,
              onPick: c.pickColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(ColoringController c) {
    final canvasSize = c.dohan!.regions.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        final transform = CanvasTransform.fit(
          Size(constraints.maxWidth, constraints.maxHeight),
          canvasSize,
        );

        return GestureDetector(
          key: const ValueKey('coloring-canvas'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => c.tapAt(transform.toCanvas(d.localPosition)),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _FittedColoringPainter(
              transform: transform,
              inner: ColoringPainter(
                shader: _shader!,
                regions: _regionsImage!,
                palette: _paletteImage!,
                lineart: _lineartImage!,
                canvasSize: canvasSize,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 도안 페인터를 화면 크기에 맞춰 배치한다.
///
/// 페인터 자신은 도안의 논리 좌표계로만 그리고, 화면에 맞추는 변환은 여기서
/// 한 번에 건다. 셰이더 좌표도 이 변환을 그대로 따라간다.
class _FittedColoringPainter extends CustomPainter {
  final CanvasTransform transform;
  final ColoringPainter inner;

  _FittedColoringPainter({required this.transform, required this.inner});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.save();
    canvas.translate(transform.offset.dx, transform.offset.dy);
    canvas.scale(transform.scale);
    inner.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FittedColoringPainter old) =>
      old.transform.scale != transform.scale ||
      old.transform.offset != transform.offset ||
      inner.shouldRepaint(old.inner);
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

/// 영역 맵을 셰이더가 읽을 RGBA 텍스처로 바꾼다.
///
/// R = ID 하위 8bit, G = ID 상위 8bit. dohan_core 의 인코딩과 같아야 한다.
Future<ui.Image> _regionsToImage(RegionMap regions) {
  final w = regions.width;
  final h = regions.height;
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final id = regions.ids[i];
    px[i * 4] = id & 0xFF;
    px[i * 4 + 1] = (id >> 8) & 0xFF;
    px[i * 4 + 2] = 0;
    px[i * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}
```

- [ ] **Step 5: main.dart 연결**

`app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'coloring/coloring_controller.dart';
import 'gallery/artwork_repository.dart';
import 'gallery/autosave.dart';
import 'library/bundled_dohan_source.dart';
import 'ui/coloring_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final docs = await getApplicationDocumentsDirectory();
  final repository = ArtworkRepository(docs);
  final controller = ColoringController(
    source: BundledDohanSource(),
    autosave: Autosave(repository: repository),
  );

  const dohanId = 'flower-01';
  const artworkId = 'flower-01-1';
  await controller.open(
    dohanId: dohanId,
    artworkId: artworkId,
    existing: await repository.load(artworkId),
  );

  runApp(KkumulApp(controller: controller));
}

class KkumulApp extends StatelessWidget {
  final ColoringController controller;

  const KkumulApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '꼬물꼬물',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246B4B)),
        useMaterial3: true,
      ),
      home: ColoringScreen(controller: controller),
    );
  }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd app && flutter test
```

Expected: PASS — 전체 통과 (smoke 1 + source 3 + transform 12 + fill_state 6 + shader 2 + command 5 + repository 7 + autosave 4 + controller 8 + screen 4 = 52개)

- [ ] **Step 7: 실제로 띄워 확인**

```bash
cd app && flutter run -d windows
```

눈으로 확인할 것:
- 도안이 화면 가운데에 비율을 지켜 들어간다
- 색을 고르고 칸을 누르면 그 칸만 칠해진다
- 선 위나 도안 바깥을 눌러도 아무 일이 없다
- 되돌리기가 직전 한 번을 지운다
- 앱을 껐다 다시 켜면 칠한 것이 남아 있다

마지막 항목이 이 계획의 완료 조건이다.

- [ ] **Step 8: 커밋**

```bash
git add app
git commit -m "feat(app): 색칠 화면과 앱 진입점"
```

---

## 완료 조건

```bash
cd app
flutter analyze          # 이슈 없음
flutter test             # 전부 통과
flutter run -d windows   # 칠하고, 끄고, 다시 켜면 남아 있다
```

## 계획 2 이후

1. **계획 3** — 브러시·크레용·스티커·지우개. 레이어 두 층을 `ColoringPainter` 에 끼우고 `Command` 를 두 종류 늘린다
2. **계획 4** — 사진 → 도안 변환. `dohan_core` 를 Isolate 에서 돌린다
3. **계획 5** — 5탭 내비게이션·갤러리·랭크·공유·보호자 게이트·연령 분기
4. 후속 문서([2026-09-21-dohan-core-pipeline-followups.md](2026-09-21-dohan-core-pipeline-followups.md))의 임계값 캘리브레이션 — 실제 선화 10장이 준비되는 대로
