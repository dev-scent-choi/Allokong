# 셸과 모아보기 구현 계획 (계획 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 하단 내비게이션 셸과 모아보기·놀기·내 정보 화면을 붙이고, 내장 도안을 12장으로 늘려 아이가 그림을 **고르고 · 칠하고 · 다시 찾을 수 있게** 한다.

**Architecture:** 색칠 화면은 탭이 아니라 셸 위에 띄우는 화면이고, 세션마다 `ColoringController` 와 `Autosave` 를 새로 만들어 pop 에서 버린다. 작품 썸네일은 화면을 나갈 때 한 번만 굽고, 없으면 그 도안의 선화로 대체한다. 내장 도안 12장은 코드로 그린 선화를 `dohan_cli` 에 통과시켜 만든다.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4 · `package:image` · `dohan_core` · `dohan_cli`

**Spec:** `docs/superpowers/specs/2026-10-06-shell-and-gallery-design.md`
(상위 스펙: `docs/superpowers/specs/2026-09-21-kkumul-coloring-app-design.md`)

---

## Global Constraints

이 절은 **모든 태스크의 요구사항에 묵시적으로 포함된다.**

- **도구 경로.** Flutter 는 PATH 에 없다. 항상 `C:\src\flutter\bin\flutter` / `C:\src\flutter\bin\dart` 를 전체 경로로 부른다.
- **테스트 실행.** 앱은 `app/` 에서 `flutter test`, 패키지는 각 디렉터리에서 `dart test`. **출력을 `grep` 으로 거르지 말 것** — 블록 버퍼링 때문에 끝난 실행이 멈춘 것처럼 보인다.
- **시작 기준선** (2026-10-06 실측): 앱 **176** · dohan_core **70** · dohan_cli **13** · dohan_gen **5**. 테스트 수는 늘기만 해야 한다.
- **정적 분석.** `app/` 에서 `flutter analyze` 가 `No issues found!` 여야 한다. `flutter_lints` 가 켜져 있어 **`prefer_const_constructors` 가 활성**이다 — 상수로 만들 수 있는 생성자에 `const` 를 빠뜨리면 린트가 난다.
- **터치 타겟 최소 64dp** (상위 스펙 10.3). 아이 손가락은 어른보다 부정확하다.
- **색만으로 의미를 전달하지 않는다** (상위 스펙 10.1). 내비 칸은 아이콘과 짧은 한글 라벨을 함께 쓴다.
- **UI 문구와 주석은 한국어.** 기존 코드 전체가 그렇다.
- **좁은 화면 기준은 320 × 640, 하단 인셋 34.** 계획 2·3 에서 쓴 것과 같다.
- **도안 캔버스는 1024² 고정** (상위 스펙 5.3).
- **품질 게이트 창** (실측): 칠할 수 있는 영역 **4개 이상 120개 이하**, 가장 작은 영역의 **내접원 지름 72px 이상**. 배경 비율은 보고만 하고 판정에 쓰지 않는다.
- **런타임에 네트워크를 쓰지 않는다.**
- **커밋 메시지**는 기존 관례를 따른다: `feat(app): …` · `fix(app): …` · `refactor(app): …` · `docs: …`, 제목은 한국어. `printf` 로 만들지 말 것(`%` 가 잘린다) — `git commit -F -` 에 heredoc 을 쓴다.

---

## 이 계획이 손대는 파일

**새로 만드는 것**

| 파일 | 책임 | 태스크 |
|---|---|---|
| `app/tools/make_dohans.dart` | 선화 12장 생성 | 2 |
| `app/lib/gallery/thumbnail.dart` | 썸네일 굽기 · `ThumbnailBaker` | 4 |
| `app/lib/coloring/coloring_route.dart` | 색칠 세션 하나의 생애 | 5 |
| `app/lib/ui/art_tile.dart` | 격자 한 칸의 틀 | 6 |
| `app/lib/gallery/gallery_screen.dart` | 모아보기 | 7 |
| `app/lib/play/play_screen.dart` | 놀기 | 8 |
| `app/lib/settings/settings_screen.dart` | 내 정보 | 9 |
| `app/lib/shell/bottom_nav.dart` | 다섯 칸 내비 | 10 |
| `app/lib/shell/shell_screen.dart` | 탭 전환과 상태 유지 | 11 |
| `app/lib/shell/placeholder_screen.dart` | `만들기`·`랭크` 자리표시자 | 11 |

**고치는 것**

| 파일 | 무엇을 | 태스크 |
|---|---|---|
| `tools/dohan_cli/bin/dohan.dart` | `--category` 에 `shape` | 1 |
| `packages/dohan_core/lib/src/dohan_package.dart` | 카테고리 목록 주석 | 1 |
| `app/pubspec.yaml` | 에셋 12 디렉터리 | 2 |
| `app/lib/library/bundled_dohan_source.dart` | `defaultIds` 12개 · `loadMeta` | 2, 8 |
| `app/lib/core/dohan_source.dart` | `loadMeta` 추가 | 8 |
| `app/lib/gallery/artwork_repository.dart` | `thumb.png` · `deleteAll` | 3 |
| `app/lib/coloring/coloring_controller.dart` | `thumbnailBaker` · `close()` | 4 |
| `app/lib/ui/coloring_screen.dart` | 썸네일 굽기 배선 · `완성` 버튼 | 4, 5 |
| `app/lib/main.dart` | 셸 띄우기 | 11 |
| `app/test/coloring_controller_test.dart` | 썸네일 테스트 · `FakeDohanSource` 에 `loadMeta` | 4, 8 |
| `app/test/coloring_screen_test.dart` | 굽기 배선 테스트 · `FakeDohanSource` 에 `loadMeta` | 4, 8 |

**지우는 것**: `app/tools/make_sample_lineart.dart` (태스크 2)

---

## 먼저 읽을 함정 셋

계획 2·3 에서 실제로 사람을 멈춰 세웠던 것들이다.

### 가. 엔진 비동기는 `testWidgets` 본문에서 완료되지 않을 수 있다

`ui.decodeImageFromPixels` 와 `ui.instantiateImageCodec` 은 엔진 콜백이라 `testWidgets` 본문의 FakeAsync 아래에서 펌프해 줄 것이 없으면 영영 완료되지 않는다. 계획 3 의 태스크 12 가 이것으로 교착했다. **위젯을 띄운 뒤 엔진 작업을 기다려야 하는 테스트는 반드시 이 순서를 쓴다:**

```dart
await tester.pumpWidget(app);
// 엔진 콜백은 FakeAsync 아래에서 완료되지 않는다. 실제 존에서 한 박자 돌린다.
await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
await tester.pumpAndSettle();
```

필요 없을 때 넣어도 해롭지 않다. 빠뜨리면 테스트가 **실패가 아니라 교착**한다.

### 나. `ByteData.buffer` 를 쓰지 말 것

`ByteData` 는 더 큰 버퍼의 조각일 수 있어 `.buffer.asUint8List()` 는 `offsetInBytes` 를 무시하고 엉뚱한 자리에서 읽는다. **언제나 `Uint8List.sublistView(data)`.**

### 다. `ColoringController.dispose()` 가 `Autosave` 를 dispose 한다

`Autosave` 하나를 셸에 두고 돌려 쓰면 첫 세션이 끝나는 순간 `_disposed = true` 가 되고, 그 뒤 `schedule()` 은 **조용히 아무 일도 하지 않는다.** 두 번째 작품부터 아이가 칠한 것이 영영 저장되지 않으면서 오류도 뜨지 않는다. **세션마다 새 `Autosave`** 를 만든다. `ArtworkRepository` 는 상태가 없으므로 공유해도 된다.

---
## Task 1: 카테고리 `shape` 를 받아들이게 한다

상위 스펙 5.2 의 `character` 자리에 `shape` 를 둔다(설계 스펙 2.2). 카테고리 목록이 **두 군데에 박혀 있어서** 고치지 않으면 태스크 2 의 도안 생성이 첫 장에서 멈춘다.

**Files:**
- Modify: `tools/dohan_cli/bin/dohan.dart:129`
- Modify: `packages/dohan_core/lib/src/dohan_package.dart:14`
- Test: `tools/dohan_cli/test/cli_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces: `dohan build --category=shape` 가 통과한다. 태스크 2 가 쓴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tools/dohan_cli/test/cli_test.dart` 의 `main()` 안에 붙인다. 파일에는 이미
`import '../bin/dohan.dart' as cli;` 와 품질 게이트를 통과하는 픽스처
`_fourBoxesImage()`(영역 4개, 최소 지름 99px), 그리고 `setUp` 이 만들어 주는
`tmp` 디렉터리가 있다 — 전부 그대로 쓴다.

```dart
  test('buildDohan 은 shape 카테고리를 받는다', () async {
    final input = File('${tmp.path}/in.png')
      ..writeAsBytesSync(img.encodePng(_fourBoxesImage()));
    final outDir = Directory('${tmp.path}/out');

    final report = await cli.buildDohan(
      input: input,
      outDir: outDir,
      id: 'shape-x',
      title: '모양',
      category: 'shape',
    );

    expect(report.passed, isTrue, reason: report.koreanSummary());
    final pkg = await readDohanPackage(outDir);
    expect(pkg.meta.category, 'shape');
  });
```

`readDohanPackage` 는 `package:dohan_core/dohan_core_io.dart` 에 있고 이미
import 돼 있다. 기존 테스트들이 결과를 어떻게 읽는지 보고 같은 방식을 쓸 것.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd tools/dohan_cli && C:\src\flutter\bin\dart test`
Expected: 새 테스트가 FAIL. `buildDohan` 자체는 `category` 를 그냥 문자열로 쓰므로 **이 단계에서는 통과할 수도 있다** — 통과하면 그대로 두고 3단계로 간다. 진짜 막는 것은 `ArgParser` 의 `allowed` 목록이고 그것은 4단계가 잡는다.

- [ ] **Step 3: 두 군데의 카테고리 목록을 고친다**

`tools/dohan_cli/bin/dohan.dart:129`:

```dart
      ..addOption('category',
          allowed: ['animal', 'car', 'dinosaur', 'shape'],
          defaultsTo: 'animal',
          help: '도안 카테고리.')
```

`packages/dohan_core/lib/src/dohan_package.dart:14` 의 문서 주석:

```dart
  /// `animal` · `car` · `dinosaur` · `shape` 중 하나.
```

- [ ] **Step 4: CLI 가 실제로 받는지 눈으로 확인한다**

Run:
```
cd tools/dohan_cli && C:\src\flutter\bin\dart run bin/dohan.dart build --help
```
Expected: `--category` 의 allowed 목록에 `shape` 가 보이고 `character` 는 없다.

- [ ] **Step 5: 테스트를 돌린다**

Run: `cd tools/dohan_cli && C:\src\flutter\bin\dart test`
Expected: PASS, 14개 (13 + 1).

Run: `cd packages/dohan_core && C:\src\flutter\bin\dart test`
Expected: PASS, 70개 (주석만 바꿨으므로 그대로).

- [ ] **Step 6: 커밋**

```bash
git add tools/dohan_cli packages/dohan_core
git commit -F - <<'EOF'
feat(dohan_cli): 카테고리 character 를 shape 로

내장 도안은 코드로 그린 자리표시자라 캐릭터를 그릴 수 없다.
ArgParser 의 allowed 목록과 dohan_package 의 문서 주석 두 군데에
박혀 있어 둘 다 고친다. 진짜 캐릭터 도안이 생기면 목록에 도로 넣는다.
EOF
```

---

## Task 2: 내장 도안 12장

4 카테고리 × 3장. 기존 `flower-01` 이 `모양` 의 한 장이 되므로 **새로 그리는 것은 11장**이지만, 생성기 하나가 12장을 모두 만든다.

**이 태스크의 코드는 2026-10-06 에 실제로 품질 게이트를 통과시켜 검증했다.** 숫자를 바꾸지 말 것 — 좌표 하나가 20px 어긋나면 분할선이 다각형 꼭짓점을 스쳐 15px 짜리 조각이 생기고 게이트에 걸린다(설계 스펙 9.1).

**Files:**
- Create: `app/tools/make_dohans.dart`
- Delete: `app/tools/make_sample_lineart.dart`
- Create: `app/assets/dohans/<12개 id>/` (생성물)
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/library/bundled_dohan_source.dart`
- Test: `app/test/bundled_dohan_source_test.dart`

**Interfaces:**
- Consumes: 태스크 1 의 `--category=shape`
- Produces: 도안 ID 12개와 카테고리 네 개. `BundledDohanSource.defaultIds` 가 12개를 돌려준다. 태스크 7·8 이 쓴다.

도안 목록:

| id | 제목 | 카테고리 | 난이도 |
|---|---|---|---|
| `animal-cat-01` | 고양이 | animal | 1 |
| `animal-fish-01` | 물고기 | animal | 1 |
| `animal-bird-01` | 새 | animal | 1 |
| `car-sedan-01` | 승용차 | car | 1 |
| `car-truck-01` | 트럭 | car | 2 |
| `car-bus-01` | 버스 | car | 2 |
| `dino-stego-01` | 스테고사우루스 | dinosaur | 2 |
| `dino-trex-01` | 티라노사우루스 | dinosaur | 3 |
| `dino-bronto-01` | 브라키오사우루스 | dinosaur | 2 |
| `flower-01` | 동그라미 꽃 | shape | 1 |
| `shape-star-01` | 별 | shape | 1 |
| `shape-house-01` | 집 | shape | 1 |

`flower-01` 은 **id 와 제목을 그대로 유지한다** — 저장된 작품이 참조하고 기존 테스트가 제목을 단언한다.

- [ ] **Step 1: 생성기를 쓴다**

`app/tools/make_dohans.dart` — 아래를 **그대로** 옮긴다.
```dart
// 내장 도안 12장의 선화를 그린다. 흰 바탕에 검은 윤곽선만 있고
// 닫힌 영역이 색칠할 자리가 된다. dohan_cli 가 그 영역을 라벨링한다.
//
// 실행:  cd app && C:/src/flutter/bin/dart run tools/make_dohans.dart <출력디렉터리>
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int kSize = 1024;
const int kInkRadius = 3; // 굵기 7px

class Pen {
  final img.Image im;
  Pen(this.im);

  void dot(double x, double y) {
    final cx = x.round(), cy = y.round();
    for (var dy = -kInkRadius; dy <= kInkRadius; dy++) {
      for (var dx = -kInkRadius; dx <= kInkRadius; dx++) {
        final px = cx + dx, py = cy + dy;
        if (px >= 0 && py >= 0 && px < kSize && py < kSize) {
          im.setPixelRgba(px, py, 0, 0, 0, 255);
        }
      }
    }
  }

  void line(double x1, double y1, double x2, double y2) {
    final n = math.max((x2 - x1).abs(), (y2 - y1).abs()).ceil() * 2 + 1;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      dot(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
  }

  void poly(List<double> pts, {bool close = true}) {
    for (var i = 0; i + 3 < pts.length; i += 2) {
      line(pts[i], pts[i + 1], pts[i + 2], pts[i + 3]);
    }
    if (close) {
      line(pts[pts.length - 2], pts[pts.length - 1], pts[0], pts[1]);
    }
  }

  void arc(double cx, double cy, double rx, double ry, double a0, double a1) {
    final steps = (math.max(rx, ry) * (a1 - a0).abs()).ceil() * 2 + 8;
    for (var i = 0; i <= steps; i++) {
      final a = a0 + (a1 - a0) * i / steps;
      dot(cx + rx * math.cos(a), cy + ry * math.sin(a));
    }
  }

  void ellipse(double cx, double cy, double rx, double ry) =>
      arc(cx, cy, rx, ry, 0, 2 * math.pi);

  void circle(double cx, double cy, double r) => ellipse(cx, cy, r, r);

  void rect(double l, double t, double r, double b) =>
      poly([l, t, r, t, r, b, l, b]);
}

typedef Draw = void Function(Pen p);

/// 도안 하나의 정의.
class Spec {
  final String id;
  final String title;
  final String category;
  final int difficulty;
  final Draw draw;
  const Spec(this.id, this.title, this.category, this.difficulty, this.draw);
}

const tau = 2 * math.pi;

final specs = <Spec>[
  // 그리는 규칙 — 실측으로 얻었다(스펙 9.1):
  //  1) 실루엣은 **닫힌 외곽선 하나**. 윤곽선끼리 교차시키지 않는다 —
  //     교차점마다 얇은 조각이 생겨 최소 지름 72px 기준에 걸린다.
  //  2) 내부를 나눌 때는 실루엣을 **완전히 가로지르는** 선을 쓴다.
  //     안에서 끝나는 선은 아무것도 나누지 못한다.
  //  3) 장식(눈·배)은 한 영역 **안에 완전히** 들어가고 지름 100px 이상.

  // ── 동물 ──────────────────────────────────────────────
  Spec('animal-cat-01', '고양이', 'animal', 1, (p) {
    // 귀까지 한 다각형으로 그린다. 귀를 따로 그려 머리와 교차시키면
    // 교차점에 33px 짜리 조각이 생긴다(실측).
    p.poly([
      230, 430, 270, 160, 430, 330, 594, 330, 754, 160, 794, 430,
      760, 700, 600, 840, 424, 840, 264, 700,
    ]);
    p.circle(400, 480, 70); // 왼쪽 눈
    p.circle(624, 480, 70); // 오른쪽 눈
    p.circle(512, 660, 70); // 코
  }),
  Spec('animal-fish-01', '물고기', 'animal', 1, (p) {
    p.poly([
      170, 450, 430, 300, 720, 330, 960, 250, 830, 512, 960, 774,
      720, 694, 430, 724, 170, 575,
    ]);
    p.line(470, 240, 470, 790); // 머리 경계
    p.line(700, 230, 700, 800); // 꼬리 경계
    p.circle(300, 505, 62);     // 눈
  }),
  Spec('animal-bird-01', '새', 'animal', 1, (p) {
    p.poly([
      90, 360, 250, 300, 400, 180, 560, 300, 820, 620, 700, 860,
      420, 880, 250, 700, 250, 430,
    ]);
    p.line(170, 530, 650, 265); // 머리 경계
    p.line(200, 600, 870, 690); // 날개 경계
    p.circle(345, 355, 60);     // 눈
  }),

  // ── 자동차 ────────────────────────────────────────────
  Spec('car-sedan-01', '승용차', 'car', 1, (p) {
    p.rect(120, 520, 904, 760);
    p.poly([260, 520, 360, 330, 680, 330, 780, 520]);
    p.line(512, 300, 512, 540);
    p.circle(290, 760, 110);
    p.circle(734, 760, 110);
  }),
  Spec('car-truck-01', '트럭', 'car', 2, (p) {
    // 짐칸과 운전석을 각각의 사각형으로 그리면 맞닿은 변에 41px 짜리
    // 조각이 생긴다(실측). 하나의 다각형으로 그리고 선으로 나눈다.
    p.poly([110, 430, 480, 430, 480, 540, 910, 540, 910, 740, 110, 740]);
    p.line(480, 400, 480, 780); // 짐칸 / 운전석
    p.circle(295, 740, 110);
    p.circle(695, 740, 110);
  }),
  Spec('car-bus-01', '버스', 'car', 2, (p) {
    p.rect(100, 330, 924, 760);
    p.line(100, 470, 924, 470);
    p.line(374, 310, 374, 490);
    p.line(650, 310, 650, 490);
    p.circle(280, 760, 110);
    p.circle(744, 760, 110);
  }),

  // ── 공룡 ──────────────────────────────────────────────
  Spec('dino-stego-01', '스테고사우루스', 'dinosaur', 2, (p) {
    p.poly([
      90, 430, 200, 340, 330, 400, 420, 230, 510, 400, 600, 230,
      690, 400, 900, 380, 990, 520, 900, 660, 620, 790, 330, 790,
      150, 620,
    ]);
    p.line(300, 300, 300, 860); // 머리 경계
    p.line(720, 300, 720, 860); // 꼬리 경계
    p.circle(480, 620, 110);    // 배
  }),
  Spec('dino-trex-01', '티라노사우루스', 'dinosaur', 3, (p) {
    p.poly([
      60, 520, 230, 430, 430, 330, 640, 250, 780, 190, 960, 300,
      940, 410, 760, 440, 680, 530, 560, 740, 330, 790, 180, 650,
    ]);
    p.line(660, 160, 660, 600); // 머리 경계
    p.line(260, 380, 300, 830); // 꼬리 경계
    p.circle(820, 310, 60);     // 눈
    p.circle(430, 580, 115);    // 배
  }),
  Spec('dino-bronto-01', '브라키오사우루스', 'dinosaur', 2, (p) {
    p.poly([
      50, 700, 220, 600, 420, 500, 580, 470, 600, 220, 700, 130,
      880, 180, 850, 330, 760, 300, 770, 520, 870, 700, 620, 840,
      330, 850, 150, 810,
    ]);
    p.line(480, 450, 920, 600); // 목 / 몸통
    p.line(540, 380, 900, 380); // 목 가로 분할
    p.circle(400, 690, 120);    // 배
  }),

  // ── 모양 ──────────────────────────────────────────────
  Spec('flower-01', '동그라미 꽃', 'shape', 1, (p) {
    for (final r in [460.0, 340.0, 220.0, 100.0]) {
      p.circle(512, 512, r);
    }
  }),
  Spec('shape-star-01', '별', 'shape', 1, (p) {
    const inner = 110.0;
    final tips = <double>[];
    final pts = <double>[];
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? 440.0 : 200.0;
      final x = 512 + r * math.cos(a);
      final y = 512 + r * math.sin(a);
      pts..add(x)..add(y);
      if (i.isEven) tips..add(x)..add(y);
    }
    p.poly(pts);
    p.circle(512, 512, inner);
    // 가운데 원에서 각 꼭짓점까지 — 원 테두리도 잉크라서 쐐기가 닫힌다.
    for (var i = 0; i + 1 < tips.length; i += 2) {
      final a = math.atan2(tips[i + 1] - 512, tips[i] - 512);
      p.line(512 + inner * math.cos(a), 512 + inner * math.sin(a),
          tips[i], tips[i + 1]);
    }
  }),
  Spec('shape-house-01', '집', 'shape', 1, (p) {
    p.poly([200, 480, 150, 480, 512, 170, 874, 480, 824, 480, 824, 880, 200, 880]);
    p.line(200, 480, 824, 480); // 지붕 / 몸체
    p.rect(300, 580, 470, 750); // 창문
    p.rect(590, 620, 750, 880); // 문
  }),
];

void main(List<String> args) {
  final dir = args.isEmpty ? '.' : args[0];
  Directory(dir).createSync(recursive: true);
  for (final s in specs) {
    final im = img.Image(width: kSize, height: kSize, numChannels: 4);
    img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
    s.draw(Pen(im));
    File('$dir/${s.id}.png').writeAsBytesSync(img.encodePng(im, level: 9));
  }
  stdout.writeln('wrote ${specs.length} line arts to $dir');
}
```

- [ ] **Step 2: 선화 12장을 그려 눈으로 확인한다**

Run:
```
cd app && C:/src/flutter/bin/dart run tools/make_dohans.dart ../.lineart-tmp
```
Expected: `wrote 12 line arts to ../.lineart-tmp`

PNG 몇 장을 열어 본다. 흰 바탕에 검은 윤곽선만 있고, 각 그림이 무엇인지 알아볼 수 있어야 한다. `.lineart-tmp` 는 중간 산출물이라 커밋하지 않는다 — 6단계에서 지운다.

- [ ] **Step 3: 품질 게이트에 통과시킨다**

`app/` 에서 아래 스크립트를 `build-dohans.sh` 라는 이름으로 임시로 만들어 실행한다(커밋하지 않는다).

```sh
#!/bin/sh
set -e
# build() 가 하위 셸에서 cd 하므로 상대 경로는 거기서 깨진다. 절대 경로로 바꾼다.
LINEART=$(cd "$1" && pwd)
DART=C:/src/flutter/bin/dart

build() {   # id  제목  카테고리  난이도
  (cd ../tools/dohan_cli && "$DART" run bin/dohan.dart build \
      --id="$1" --title="$2" --category="$3" --difficulty="$4" \
      "$LINEART/$1.png" "../../app/assets/dohans/$1")
}

build animal-cat-01    "고양이"           animal   1
build animal-fish-01   "물고기"           animal   1
build animal-bird-01   "새"               animal   1
build car-sedan-01     "승용차"           car      1
build car-truck-01     "트럭"             car      2
build car-bus-01       "버스"             car      2
build dino-stego-01    "스테고사우루스"   dinosaur 2
build dino-trex-01     "티라노사우루스"   dinosaur 3
build dino-bronto-01   "브라키오사우루스" dinosaur 2
build flower-01        "동그라미 꽃"      shape    1
build shape-star-01    "별"               shape    1
build shape-house-01   "집"               shape    1
```

Run: `cd app && sh build-dohans.sh ../.lineart-tmp`

Expected — **열두 줄 모두 `통과`**. 2026-10-06 실측값과 같아야 한다:

```
animal-cat-01: 통과 — 영역 4개, 배경 72.7%, 최소 영역 지름 91px
animal-fish-01: 통과 — 영역 4개, 배경 74.2%, 최소 영역 지름 81px
animal-bird-01: 통과 — 영역 4개, 배경 71.8%, 최소 영역 지름 79px
car-sedan-01: 통과 — 영역 7개, 배경 69.8%, 최소 영역 지름 91px
car-truck-01: 통과 — 영역 6개, 배경 76.3%, 최소 영역 지름 91px
car-bus-01: 통과 — 영역 8개, 배경 61.6%, 최소 영역 지름 91px
dino-stego-01: 통과 — 영역 4개, 배경 68.3%, 최소 영역 지름 145px
dino-trex-01: 통과 — 영역 5개, 배경 74.0%, 최소 영역 지름 79px
dino-bronto-01: 통과 — 영역 4개, 배경 71.6%, 최소 영역 지름 117px
flower-01: 통과 — 영역 4개, 배경 35.4%, 최소 영역 지름 105px
shape-star-01: 통과 — 영역 6개, 배경 74.1%, 최소 영역 지름 83px
shape-house-01: 통과 — 영역 4개, 배경 64.5%, 최소 영역 지름 133px
```

**한 줄이라도 `리젝트` 가 나오면 좌표를 고치지 말고 멈추고 보고할 것.** 위 숫자는 실측이므로, 다르다면 생성기를 옮겨 적는 과정에서 숫자가 틀렸거나 파이프라인이 바뀐 것이다. 둘 다 혼자 추측해서 고칠 일이 아니다.

각 도안은 폴더 하나에 **네 파일**을 만든다: `lineart.png` · `lineart@2x.png` · `regions.png` · `meta.json`. `lineart@2x.png` 는 `buildDohan` 이 의도적으로 쓰는 고밀도용 선화다 — 지금은 읽는 코드가 없지만 **지우지 않는다**(설계 스펙 9절).

- [ ] **Step 4: pubspec 에 에셋 12 디렉터리를 등록한다**

`app/pubspec.yaml` 의 `assets:` 블록을 통째로 아래로 바꾼다.

```yaml
  assets:
    - assets/dohans/animal-cat-01/
    - assets/dohans/animal-fish-01/
    - assets/dohans/animal-bird-01/
    - assets/dohans/car-sedan-01/
    - assets/dohans/car-truck-01/
    - assets/dohans/car-bus-01/
    - assets/dohans/dino-stego-01/
    - assets/dohans/dino-trex-01/
    - assets/dohans/dino-bronto-01/
    - assets/dohans/flower-01/
    - assets/dohans/shape-star-01/
    - assets/dohans/shape-house-01/
    - assets/stickers/
```

- [ ] **Step 5: `defaultIds` 를 12개로 늘린다**

`app/lib/library/bundled_dohan_source.dart`:

```dart
  /// 번들에 실린 도안 ID. pubspec 의 `assets` 목록과 짝이 맞아야 한다.
  ///
  /// 순서가 `놀기` 의 카테고리별 격자 순서가 된다.
  static const defaultIds = [
    'animal-cat-01',
    'animal-fish-01',
    'animal-bird-01',
    'car-sedan-01',
    'car-truck-01',
    'car-bus-01',
    'dino-stego-01',
    'dino-trex-01',
    'dino-bronto-01',
    'flower-01',
    'shape-star-01',
    'shape-house-01',
  ];
```

- [ ] **Step 6: 옛 생성기와 중간 산출물을 지운다**

```bash
rm app/tools/make_sample_lineart.dart
rm app/build-dohans.sh
rm -rf .lineart-tmp
```

`make_sample_lineart.dart` 는 자기 헤더에 *"실제 도안 에셋이 준비되면 이 파일은 지운다"* 고 적혀 있다. 이제 그때다.

- [ ] **Step 7: 테스트를 쓴다**

`app/test/bundled_dohan_source_test.dart` 의 `main()` 안에 붙인다. 기존 테스트들은 그대로 둔다(`flower-01` 이 id 와 제목을 유지하므로 계속 통과한다).

```dart
  test('내장 도안이 12장이고 네 카테고리에 셋씩이다', () async {
    final source = BundledDohanSource();
    final ids = await source.listIds();

    expect(ids, hasLength(12));
    expect(ids.toSet(), hasLength(12), reason: 'id 가 겹치면 안 된다');

    final byCategory = <String, List<String>>{};
    for (final id in ids) {
      final pkg = await source.load(id);
      byCategory.putIfAbsent(pkg.meta.category, () => []).add(id);
      expect(pkg.meta.id, id, reason: 'meta.id 와 폴더 이름이 어긋났다');
      expect(pkg.regions.width, 1024);
      expect(pkg.meta.title, isNotEmpty);
    }

    expect(byCategory.keys.toSet(), {'animal', 'car', 'dinosaur', 'shape'});
    for (final entry in byCategory.entries) {
      expect(entry.value, hasLength(3), reason: '${entry.key} 가 3장이 아니다');
    }
  });

  test('도안마다 칠할 수 있는 영역이 넷 이상이다', () async {
    final source = BundledDohanSource();
    for (final id in await source.listIds()) {
      final pkg = await source.load(id);
      expect(pkg.regions.fillableRegionCount, greaterThanOrEqualTo(4),
          reason: '$id 는 칠할 곳이 넷도 안 된다');
      expect(pkg.regions.fillableRegionCount, lessThanOrEqualTo(120),
          reason: '$id 는 영역이 너무 많다');
    }
  });
```

- [ ] **Step 8: 테스트를 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 178개 (176 + 2).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: 커밋**

```bash
git add app/tools app/assets app/pubspec.yaml app/lib/library app/test
git commit -F - <<'EOF'
feat(app): 내장 도안 12장

4 카테고리(동물·자동차·공룡·모양) × 3장. 코드로 그린 선화를
dohan_cli 에 통과시켰다. 열두 장 모두 품질 게이트 통과 —
영역 4~8개, 최소 내접원 지름 79~145px.

그리는 규칙은 실측으로 얻었다: 실루엣은 닫힌 외곽선 하나,
내부는 완전히 가로지르는 선으로 나누고, 장식은 한 영역 안에
완전히 들어간다. 윤곽선끼리 교차시키면 교차점마다 얇은 조각이
생겨 72px 기준에 걸린다.

flower-01 은 id 와 제목을 유지하고 카테고리만 animal -> shape 로
바로잡았다. make_sample_lineart.dart 는 제 역할을 마쳐 지운다.
EOF
```

---
## Task 3: 저장소에 `thumb.png` 와 전체 삭제

상위 스펙 11장의 작품 폴더 구조는 `artwork.json` · `brush.png` · `stickers.json` · **`thumb.png`** 네 개다. 계획 2·3 이 앞의 셋을 구현했고 이 태스크가 남은 하나를 채운다. 더불어 `내 정보` 의 데이터 초기화가 쓸 전체 삭제를 붙인다.

**Files:**
- Modify: `app/lib/gallery/artwork_repository.dart`
- Test: `app/test/artwork_repository_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `Future<void> ArtworkRepository.saveThumbnail(String id, Uint8List png)`
  - `Future<Uint8List?> ArtworkRepository.loadThumbnail(String id)` — 없으면 `null`
  - `Future<void> ArtworkRepository.deleteAll()`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/artwork_repository_test.dart` 의 `main()` 안에 붙인다. 기존 테스트가 임시 디렉터리(`root`)를 어떻게 만드는지 보고 같은 방식을 쓸 것. 아래는 `root` 라는 이름의 `Directory` 가 `setUp` 에서 준비된다고 가정한 코드다 — 이름이 다르면 맞춰 바꾼다.

```dart
  test('썸네일을 쓰고 다시 읽는다', () async {
    final repo = ArtworkRepository(root);
    final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

    await repo.saveThumbnail('w1', png);

    expect(await repo.loadThumbnail('w1'), png);
  });

  test('썸네일이 없으면 null 이다', () async {
    expect(await ArtworkRepository(root).loadThumbnail('없는작품'), isNull);
  });

  test('썸네일을 써도 작품 파일은 그대로다', () async {
    final repo = ArtworkRepository(root);
    await repo.save(Artwork(
      id: 'w1',
      dohanId: 'flower-01',
      fills: const {2: 0xFFFF0000},
      updatedAt: DateTime.utc(2026, 10, 6),
    ));

    await repo.saveThumbnail('w1', Uint8List.fromList([1, 2, 3]));

    final loaded = await repo.load('w1');
    expect(loaded, isNotNull);
    expect(loaded!.fills[2], 0xFFFF0000);
  });

  test('전체 삭제는 작품을 모두 지운다', () async {
    final repo = ArtworkRepository(root);
    for (final id in ['w1', 'w2', 'w3']) {
      await repo.save(Artwork(
        id: id,
        dohanId: 'flower-01',
        fills: const {},
        updatedAt: DateTime.utc(2026, 10, 6),
      ));
    }
    expect(await repo.listAll(), hasLength(3));

    await repo.deleteAll();

    expect(await repo.listAll(), isEmpty);
    expect(await repo.load('w1'), isNull);
  });

  test('전체 삭제는 settings.json 을 건드리지 않는다', () async {
    // 연령대는 아이의 작품이 아니라 보호자의 설정이다. 작품을 지웠다고
    // 다시 고르게 할 이유가 없다.
    final repo = ArtworkRepository(root);
    final settings = File('${root.path}/settings.json')
      ..writeAsStringSync('{"ageMode":"child"}');
    await repo.save(Artwork(
      id: 'w1',
      dohanId: 'flower-01',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 6),
    ));

    await repo.deleteAll();

    expect(settings.existsSync(), isTrue);
    expect(settings.readAsStringSync(), contains('child'));
  });

  test('작품이 하나도 없을 때 전체 삭제해도 터지지 않는다', () async {
    await ArtworkRepository(root).deleteAll();
    expect(await ArtworkRepository(root).listAll(), isEmpty);
  });
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/artwork_repository_test.dart`
Expected: FAIL — `saveThumbnail` · `loadThumbnail` · `deleteAll` 이 정의되지 않았다는 컴파일 오류.

- [ ] **Step 3: 구현한다**

`app/lib/gallery/artwork_repository.dart` 의 `_brushFileFor` 아래에 붙인다:

```dart
  File _thumbFileFor(String id) => File('${_dirFor(id).path}/thumb.png');
```

그리고 `delete` 위에 세 메서드를 더한다:

```dart
  /// 갤러리 썸네일을 쓴다.
  ///
  /// 자동 저장과 달리 색칠 화면을 **나갈 때 한 번만** 불린다. 굽는 데 드는
  /// 비용(PNG 인코딩 실측 39ms)을 그리는 동안 0 으로 유지하기 위해서다.
  Future<void> saveThumbnail(String id, Uint8List png) async {
    final dir = _dirFor(id);
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/thumb.png.tmp');
    await tmp.writeAsBytes(png, flush: true);
    await tmp.rename(_thumbFileFor(id).path);
  }

  /// 썸네일. 없으면 `null` — 부르는 쪽이 그 도안의 선화로 대체한다.
  ///
  /// 앱이 강제 종료되어 썸네일을 굽지 못한 경우가 정상 경로에 있다.
  Future<Uint8List?> loadThumbnail(String id) async {
    try {
      return await _thumbFileFor(id).readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  /// 작품을 **전부** 지운다. `내 정보` 의 데이터 초기화에서만 부른다.
  ///
  /// `artworks/` 폴더만 지우므로 `settings.json` 은 남는다 — 연령대는
  /// 아이의 작품이 아니라 보호자의 설정이다.
  Future<void> deleteAll() async {
    if (_artworksDir.existsSync()) {
      await _artworksDir.delete(recursive: true);
    }
  }
```

- [ ] **Step 4: 테스트를 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 184개 (178 + 6).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app/lib/gallery/artwork_repository.dart app/test/artwork_repository_test.dart
git commit -F - <<'GITEOF'
feat(app): 저장소에 thumb.png 와 전체 삭제

상위 스펙 11장의 작품 폴더 네 파일 중 마지막. 임시 파일에 쓰고
rename 하는 것은 나머지 셋과 같다. 없으면 null 을 주고 부르는
쪽이 선화로 대체한다.

deleteAll 은 artworks/ 만 지운다 — settings.json 은 보호자의
설정이라 남긴다.
GITEOF
```

---

## Task 4: 썸네일 굽기

색칠 화면을 나갈 때 지금 보이는 그대로를 256² PNG 로 굽는다.

**굽는 주체가 컨트롤러가 아니라는 점이 핵심이다.** 합성에 필요한 셰이더·영역 텍스처·팔레트·선화·스티커 이미지는 전부 `_ColoringScreenState` 가 들고 있다. 컨트롤러로 옮기는 것은 큰 수술이므로 이미 있는 패턴을 그대로 쓴다 — `Autosave` 가 `BrushBaker` 를 받는 것처럼 컨트롤러가 `ThumbnailBaker` 를 받고, 화면이 텍스처를 다 올린 뒤 자기 굽기 함수를 꽂는다.

**Files:**
- Create: `app/lib/gallery/thumbnail.dart`
- Create: `app/test/thumbnail_test.dart`
- Modify: `app/lib/coloring/coloring_controller.dart`
- Modify: `app/lib/ui/coloring_screen.dart`
- Test: `app/test/coloring_controller_test.dart`
- Test: `app/test/coloring_screen_test.dart`

**Interfaces:**
- Consumes: `ArtworkRepository.saveThumbnail` (태스크 3)
- Produces:
  - `const int kThumbnailSize = 256`
  - `typedef ThumbnailBaker = Future<Uint8List?> Function()`
  - `Future<Uint8List?> bakeThumbnail(ColoringPainter painter, int canvasSize)`
  - `ColoringController.thumbnailBaker` — 쓰기 가능한 필드
  - `ColoringController.close()` 가 썸네일까지 쓴다

- [ ] **Step 1: 실패하는 테스트를 쓴다 — 상태가 아니라 픽셀을 본다**

계획 3 에서 테스트 173개가 전부 통과하는 동안 아이가 손가락을 끌어도 화면에 아무것도 나타나지 않았다. 전부 컨트롤러 **상태**만 단언했기 때문이다. 썸네일은 **결과 픽셀**로 확인한다.

`app/test/thumbnail_test.dart` 를 새로 만든다. `testWidgets` 가 아니라 평범한 `test` 에 `TestWidgetsFlutterBinding.ensureInitialized()` 를 쓴다 — `app/test/fill_shader_test.dart` 와 같은 방식이고, FakeAsync 가 없어 엔진 콜백이 그냥 완료된다.

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/coloring_painter.dart';
import 'package:kkumul/coloring/fill_state.dart';
import 'package:kkumul/gallery/thumbnail.dart';

Future<ui.Image> _rgba(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// 왼쪽 절반이 ID 2, 오른쪽 절반이 ID 3 인 정사각 인덱스맵.
Future<ui.Image> _halves(int n) {
  final px = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final i = (y * n + x) * 4;
      final id = x < n ~/ 2 ? 2 : 3;
      px[i] = id & 0xFF;
      px[i + 1] = (id >> 8) & 0xFF;
      px[i + 3] = 255;
    }
  }
  return _rgba(px, n, n);
}

Future<ui.Image> _transparent(int w, int h) => _rgba(Uint8List(w * h * 4), w, h);

/// PNG 바이트를 디코딩해 픽셀을 읽을 수 있게 한다.
Future<(int, int, ByteData)> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final data =
      (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (frame.image.width, frame.image.height, data);
}

Future<ColoringPainter> _painter(int n, FillState fills) async {
  final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
  return ColoringPainter(
    shader: program.fragmentShader(),
    regions: await _halves(n),
    palette: await fills.paletteImage(),
    lineart: await _transparent(n, n),
    canvasSize: n,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('칠한 색이 썸네일 픽셀에 그대로 나온다', () async {
    const n = 64;
    final fills = FillState()..setFill(2, const Color(0xFFFF0000));

    final png = await bakeThumbnail(await _painter(n, fills), n);

    expect(png, isNotNull);
    final (w, h, d) = await _decode(png!);
    expect(w, kThumbnailSize);
    expect(h, kThumbnailSize);

    List<int> at(int x, int y) {
      final i = (y * w + x) * 4;
      return [d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2)];
    }

    expect(at(kThumbnailSize ~/ 4, kThumbnailSize ~/ 2), [255, 0, 0],
        reason: '왼쪽 절반은 칠한 빨강이어야 한다');
    expect(at(kThumbnailSize * 3 ~/ 4, kThumbnailSize ~/ 2), [255, 255, 255],
        reason: '칠하지 않은 오른쪽은 흰 배경이 비친다');
  });

  test('아무것도 안 칠해도 흰 정사각형이 나온다', () async {
    const n = 64;

    final png = await bakeThumbnail(await _painter(n, FillState()), n);

    final (w, h, d) = await _decode(png!);
    expect(w, kThumbnailSize);
    expect(h, kThumbnailSize);
    expect([d.getUint8(0), d.getUint8(1), d.getUint8(2)], [255, 255, 255]);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/thumbnail_test.dart`
Expected: FAIL — `package:kkumul/gallery/thumbnail.dart` 가 없다는 컴파일 오류.

- [ ] **Step 3: `thumbnail.dart` 를 만든다**

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../coloring/coloring_painter.dart';

/// 갤러리 썸네일 한 변의 픽셀 수.
///
/// 2열 격자의 한 칸이 약 144dp 다. 256 이면 고해상도 화면에서도 충분하고,
/// 1024² 를 그대로 쓰는 것보다 픽셀 수가 16 배 적다.
const int kThumbnailSize = 256;

/// 썸네일을 굽는 함수. 화면이 텍스처를 다 올린 뒤 컨트롤러에 꽂는다.
///
/// 텍스처가 아직 없으면 `null` 을 돌려준다 — 그때는 쓰지 않는다.
typedef ThumbnailBaker = Future<Uint8List?> Function();

/// 합성된 도안을 [kThumbnailSize] 정사각 PNG 로 굽는다.
///
/// [painter] 는 도안의 논리 좌표계([canvasSize] × [canvasSize])로 그린다.
/// 여기서 축소 변환을 한 번 걸면 흰 배경·채움·브러시·선화·스티커가 모두
/// 그대로 줄어든다 — 화면에 보이던 것과 같은 그림이다.
Future<Uint8List?> bakeThumbnail(
  ColoringPainter painter,
  int canvasSize,
) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.scale(kThumbnailSize / canvasSize);
  painter.paint(canvas, ui.Size(canvasSize.toDouble(), canvasSize.toDouble()));
  final picture = rec.endRecording();
  final image = await picture.toImage(kThumbnailSize, kThumbnailSize);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return null;
  // ByteData 는 더 큰 버퍼의 조각일 수 있다. .buffer 를 그대로 쓰면
  // offsetInBytes 를 무시해 엉뚱한 자리에서 읽는다.
  return Uint8List.sublistView(data);
}
```

- [ ] **Step 4: 통과를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/thumbnail_test.dart`
Expected: PASS, 2개.

- [ ] **Step 5: 컨트롤러 테스트를 쓰고 실패를 확인한다**

`app/test/coloring_controller_test.dart` 의 `main()` 안에 붙인다. 필요한 import(`dart:io` · `dart:typed_data` · `dart:ui` · `ArtworkRepository` · `Autosave`)는 이미 전부 있다. 여기서는 목이 아니라 **실제 디스크에 쓰는 `Autosave`** 가 필요하다.

**이 파일의 `FakeDohanSource` 캔버스는 4 × 2 다** — 다른 테스트 파일의 64 × 64 와 다르다. 좌표를 쓸 때 주의할 것.

```dart
  test('화면을 나가면 썸네일을 굽고 저장한다', () async {
    final root = Directory.systemTemp.createTempSync('kkumul_thumb_');
    addTearDown(() => root.deleteSync(recursive: true));
    final repository = ArtworkRepository(root);
    final controller = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(repository: repository),
    );
    addTearDown(controller.dispose);
    await controller.open(dohanId: 'fake', artworkId: 'w1');

    controller.thumbnailBaker =
        () async => Uint8List.fromList([137, 80, 78, 71, 9]);
    await controller.close();

    expect(await repository.loadThumbnail('w1'),
        Uint8List.fromList([137, 80, 78, 71, 9]));
  });

  test('굽는 함수가 없으면 썸네일을 쓰지 않는다', () async {
    final root = Directory.systemTemp.createTempSync('kkumul_thumb_');
    addTearDown(() => root.deleteSync(recursive: true));
    final repository = ArtworkRepository(root);
    final controller = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(repository: repository),
    );
    addTearDown(controller.dispose);
    await controller.open(dohanId: 'fake', artworkId: 'w1');

    await controller.close();

    expect(await repository.loadThumbnail('w1'), isNull);
  });

  test('그리는 동안에는 굽지 않고 나갈 때 한 번 굽는다', () async {
    // 계획 3 이 브러시 굽기를 "바뀌었을 때만" 으로 만들어 지켜 낸
    // "그리는 동안 0" 을 썸네일이 무너뜨리면 안 된다.
    final root = Directory.systemTemp.createTempSync('kkumul_thumb_');
    addTearDown(() => root.deleteSync(recursive: true));
    final controller = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(repository: ArtworkRepository(root)),
    );
    addTearDown(controller.dispose);
    await controller.open(dohanId: 'fake', artworkId: 'w1');

    var bakes = 0;
    controller.thumbnailBaker = () async {
      bakes++;
      return Uint8List.fromList([1, 2, 3]);
    };

    // 이 파일의 FakeDohanSource 캔버스는 **4 x 2** 다(64 x 64 가 아니다).
    // 영역 2 는 x < 2, 영역 3 은 x >= 2.
    controller.tapAt(const Offset(0.5, 0.5));
    controller.tapAt(const Offset(2.5, 0.5));
    controller.undo();
    expect(bakes, 0, reason: '칠하는 동안에는 한 번도 굽지 않는다');

    await controller.close();

    expect(bakes, 1, reason: '나갈 때 한 번이다');
  });

  test('굽다가 터져도 close() 는 조용히 끝난다', () async {
    // 화면이 사라지는 중이면 텍스처가 이미 해제됐을 수 있다. 썸네일이
    // 없으면 모아보기가 선화로 대체하므로 아이가 잃는 것은 없다.
    final root = Directory.systemTemp.createTempSync('kkumul_thumb_');
    addTearDown(() => root.deleteSync(recursive: true));
    final repository = ArtworkRepository(root);
    final controller = ColoringController(
      source: FakeDohanSource(),
      autosave: Autosave(repository: repository),
    );
    addTearDown(controller.dispose);
    await controller.open(dohanId: 'fake', artworkId: 'w1');

    controller.thumbnailBaker = () async => throw StateError('텍스처 없음');

    await expectLater(controller.close(), completes);
    expect(await repository.loadThumbnail('w1'), isNull);
  });
```

Run: `cd app && C:\src\flutter\bin\flutter test test/coloring_controller_test.dart`
Expected: FAIL — `thumbnailBaker` 가 없다.

- [ ] **Step 6: 컨트롤러를 고친다**

`app/lib/coloring/coloring_controller.dart` 의 import 에 더한다:

```dart
import '../gallery/thumbnail.dart';
```

필드를 더한다(`_stickerSeq` 아래가 좋다):

```dart
  /// 화면을 떠날 때 썸네일을 굽는 함수. 화면이 텍스처를 다 올린 뒤 꽂는다.
  ///
  /// 컨트롤러가 직접 구울 수 없는 것은 합성에 필요한 셰이더·영역 텍스처·
  /// 팔레트·선화·스티커 이미지를 전부 화면이 들고 있기 때문이다.
  /// `Autosave` 가 `BrushBaker` 를 받는 것과 같은 모양이다.
  ThumbnailBaker? thumbnailBaker;
```

`close()` 를 통째로 바꾼다:

```dart
  /// 화면을 떠나기 전에 예약된 저장을 마무리하고 썸네일을 굽는다.
  ///
  /// 생명주기 콜백(앱이 물러날 때)에서도 불린다. 그때도 굽는 것이 맞다 —
  /// 강제 종료로 썸네일 없는 작품이 생기는 경우를 줄여 준다.
  Future<void> close() async {
    await autosave.flush();

    final bake = thumbnailBaker;
    final id = _artworkId;
    if (bake == null || id == null) return;
    try {
      final png = await bake();
      if (png != null) await autosave.repository.saveThumbnail(id, png);
    } on Object catch (error) {
      // 썸네일이 없으면 모아보기가 선화로 대체한다. 그림을 잃는 것이
      // 아니므로 여기서 멈춰 세울 이유가 없다.
      debugPrint('썸네일을 굽지 못했습니다 — 선화로 대체됩니다: $error');
    }
  }
```

- [ ] **Step 7: 화면이 굽기 함수를 꽂게 한다**

`app/lib/ui/coloring_screen.dart` 의 import 에 더한다:

```dart
import '../gallery/thumbnail.dart';
```

`_prepare()` 의 `setState(...)` 호출 **바로 뒤에** 한 줄 더한다:

```dart
    // 텍스처가 다 올라온 지금부터 썸네일을 구울 수 있다.
    widget.controller.thumbnailBaker = _bakeThumbnail;
```

`_refreshPalette` 아래에 굽기 함수를 더한다:

```dart
  /// 지금 화면에 보이는 그대로를 썸네일로 굽는다.
  Future<Uint8List?> _bakeThumbnail() async {
    final dohan = widget.controller.dohan;
    final shader = _shader;
    final regions = _regionsImage;
    final palette = _paletteImage;
    final lineart = _lineartImage;
    if (dohan == null ||
        shader == null ||
        regions == null ||
        palette == null ||
        lineart == null) {
      return null;
    }

    final c = widget.controller;
    return bakeThumbnail(
      ColoringPainter(
        shader: shader,
        regions: regions,
        palette: palette,
        lineart: lineart,
        canvasSize: dohan.regions.width,
        brush: c.state.brush,
        brushRevision: c.state.brush.revision,
        paintableMask: c.paintableMask,
        stickers: c.state.stickers.stickers,
        stickerImages: _stickerImages,
      ),
      dohan.regions.width,
    );
  }
```

`dispose()` 에서 **이미지를 해제하기 전에** 꽂아 둔 함수를 뺀다:

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onChanged);
    // 이미지를 해제하기 전에 뺀다. 그러지 않으면 생명주기 close() 가
    // 이미 해제된 텍스처로 그리려 든다.
    widget.controller.thumbnailBaker = null;
    _shader?.dispose();
    // ... 아래는 그대로 둔다
```

- [ ] **Step 8: 화면 쪽 테스트를 쓴다**

`app/test/coloring_screen_test.dart` 의 `main()` 안에 붙인다. 이 파일의 `setUp` 이 `controller` 를 만들어 열어 둔다.

```dart
  testWidgets('화면이 뜨면 썸네일 굽기가 꽂히고 사라지면 빠진다', (tester) async {
    expect(controller.thumbnailBaker, isNull, reason: '처음에는 없다');

    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(controller.thumbnailBaker, isNotNull,
        reason: '텍스처가 올라오면 구울 수 있어야 한다');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    expect(controller.thumbnailBaker, isNull,
        reason: '해제된 텍스처로 그리려 들면 안 된다');
  });
```

- [ ] **Step 9: 전부 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 191개 (184 + 2 + 4 + 1).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: 커밋**

```bash
git add app/lib/gallery/thumbnail.dart app/lib/coloring/coloring_controller.dart app/lib/ui/coloring_screen.dart app/test
git commit -F - <<'GITEOF'
feat(app): 화면을 나갈 때 썸네일을 굽는다

256 정사각 PNG 한 장. 디바운스마다 굽지 않는 이유는 비용이다 —
PNG 인코딩이 실측 39ms 라, 계획 3 이 브러시 굽기를 "바뀌었을 때만"
으로 만들어 지켜 낸 "그리는 동안 0" 을 무너뜨린다.

굽는 주체는 컨트롤러가 아니라 화면이다. 합성에 필요한 셰이더와
텍스처를 화면이 들고 있어서, Autosave 의 BrushBaker 와 같은 모양의
ThumbnailBaker 콜백으로 받는다. 화면이 사라질 때 콜백을 빼므로
해제된 텍스처로 그리는 일이 없다.
GITEOF
```

---
## Task 5: 색칠 세션 — 셸 위에 띄우고, 나갈 때 버린다

이 계획에서 **구조적으로 가장 중요한 태스크**다. 색칠을 탭이 아니라 띄우는 화면으로 만들고 세션마다 컨트롤러와 `Autosave` 를 새로 만들면, 후속 문서 세 곳에 "다음 계획이 건드리는 순간 터진다"고 적어 둔 항목이 **고쳐지는 것이 아니라 발생할 수 없게** 된다(설계 스펙 4절):

- 계획 2 후속 §1.1 — `open()` 도중 들어온 탭이 사라진다 → `open()` 이 컨트롤러당 한 번뿐이다
- 계획 2 후속 §3.3 — 두 번째 `open()` 에서 `_prepare()` 가 다시 안 돈다 → 두 번째 `open()` 이 없다
- 계획 3 후속 §1.1 — `ageMode` 를 유아로 바꾸면 아이가 갇힌다 → 다음에 열 때 새 컨트롤러가 현재 설정을 읽는다

**Files:**
- Create: `app/lib/coloring/coloring_route.dart`
- Create: `app/test/coloring_route_test.dart`
- Modify: `app/lib/ui/coloring_screen.dart` (`완성` 버튼)

**Interfaces:**
- Consumes: `ColoringController` · `Autosave` · `ArtworkRepository` · `DohanSource` · `AgeMode` · `ColoringScreen`
- Produces:
  - `String newArtworkId(String dohanId)`
  - `Future<void> openColoring(BuildContext context, {required DohanSource source, required ArtworkRepository repository, required AgeMode ageMode, required String dohanId, required String artworkId})`
  - `class ColoringSession extends StatefulWidget` — 같은 인자를 받는 위젯
  - `typedef OpenColoring = Future<void> Function({required String dohanId, required String artworkId})`
  - `ColoringScreen` 이 `Future<void> Function()? onFinish` 를 받는다

### 꼭 지킬 것 셋

1. **세션마다 새 `Autosave`.** `ColoringController.dispose()` 가 `autosave.dispose()` 를 부른다. 하나를 돌려 쓰면 두 번째 작품부터 `schedule()` 이 조용히 아무 일도 하지 않는다.
2. **`-복구-` 경로를 잃지 말 것.** 지금 `main()` 에 있는 복구 로직을 그대로 옮긴다. 두고 오면 저장 파일이 한 번 깨진 작품을 아이가 영영 못 연다.
3. **나가는 길은 하나로 모은다.** `완성` 버튼과 기기 뒤로가기가 둘 다 `close()` 를 **먼저** 기다린 뒤 pop 해야 한다. 그냥 pop 하면 화면이 먼저 사라져서 썸네일을 구울 텍스처가 이미 해제된 뒤가 된다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/coloring_route_test.dart` 를 새로 만든다.

**엔진 비동기 주의**: `ColoringSession.initState` 가 `controller.open()` 을 띄우고, 그 안의 `buildPaintableMask` 는 엔진 콜백이다. `testWidgets` 본문의 FakeAsync 아래에서 펌프해 줄 것이 없으면 완료되지 않는다 — 아래 `_settle` 헬퍼를 **모든 테스트에서** 쓴다. 빠뜨리면 테스트가 실패가 아니라 **교착**한다.

```dart
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

/// 엔진 콜백(ui.decodeImageFromPixels)은 testWidgets 본문의 FakeAsync
/// 아래에서 완료되지 않는다. 실제 존에서 한 박자 돌려 준 뒤 펌프한다.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
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
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openColoring(
              context,
              source: FakeDohanSource(),
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
    final box = tester.getRect(find.byKey(const ValueKey('coloring-canvas')));
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();
  }

  testWidgets('여는 동안 로딩을 보여주고 열리면 캔버스가 뜬다', (tester) async {
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await tester.pump(); // 라우트가 밀려 올라간다. open() 은 아직 안 끝났다

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _settle(tester);

    expect(find.byKey(const ValueKey('coloring-canvas')), findsOneWidget);
  });

  testWidgets('완성을 누르면 셸로 돌아가고 칠한 것이 저장된다', (tester) async {
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester);

    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _settle(tester);

    expect(find.text('열기'), findsOneWidget, reason: '셸로 돌아와야 한다');
    final saved = await repository.load('w1');
    expect(saved, isNotNull);
    expect(saved!.fills, isNotEmpty);
  });

  testWidgets('나갔다 다시 들어오면 칠한 것이 그대로다', (tester) async {
    // 설계 스펙 2.3 이 "확인 없이 나가도 된다" 고 한 근거 그 자체다.
    // 잃는 것이 없어야 확인 대화상자를 뺄 수 있다.
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester);
    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _settle(tester);

    await tester.tap(find.text('열기'));
    await _settle(tester);

    // 왼쪽 절반(영역 2)이 이미 칠해져 있으므로 다시 칠해도 늘지 않는다.
    final saved = await repository.load('w1');
    expect(saved!.fills.keys, contains(2),
        reason: '다시 열었을 때 칠한 것이 돌아와야 한다');

    await tester.tap(find.text('완성'));
    await _settle(tester);
    expect((await repository.load('w1'))!.fills.keys, contains(2));
  });

  testWidgets('두 번째 작품도 저장된다', (tester) async {
    // Autosave 를 세션끼리 돌려 쓰면 첫 세션의 dispose() 가 그것을
    // dispose 해 버려, 두 번째부터 schedule() 이 조용히 아무 일도 하지
    // 않는다. 오류도 안 뜨고 그림만 사라진다.
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester);
    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _settle(tester);

    await tester.pumpWidget(host(artworkId: 'w2'));
    await tester.tap(find.text('열기'));
    await _settle(tester);
    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _settle(tester);

    expect((await repository.load('w1'))?.fills, isNotEmpty);
    expect((await repository.load('w2'))?.fills, isNotEmpty,
        reason: '두 번째 세션의 Autosave 가 죽어 있으면 여기서 빈다');
  });

  testWidgets('연령대를 바꿔 열면 그 설정이 적용된다', (tester) async {
    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester);
    expect(find.byType(ToolButton), findsNothing, reason: '유아는 도구 줄이 없다');
    await tester.tap(find.text('완성'));
    await _settle(tester);

    await tester.pumpWidget(host(artworkId: 'w2', ageMode: AgeMode.child));
    await tester.tap(find.text('열기'));
    await _settle(tester);

    expect(find.byType(ToolButton), findsNWidgets(5),
        reason: '새 세션은 새 컨트롤러라 현재 설정을 읽는다');
  });

  testWidgets('저장 파일이 깨졌으면 복구 id 로 연다', (tester) async {
    // main() 에 있던 복구 경로다. 같은 id 로 새로 시작하면 자동 저장이
    // 잠깐 못 읽었을 뿐일지 모르는 멀쩡한 파일을 덮어쓴다.
    Directory('${root.path}/artworks/w1').createSync(recursive: true);
    File('${root.path}/artworks/w1/artwork.json')
        .writeAsStringSync('{"id":"w1"'); // 닫히지 않은 JSON

    await tester.pumpWidget(host(artworkId: 'w1'));
    await tester.tap(find.text('열기'));
    await _settle(tester);
    await paintLeft(tester);
    await tester.tap(find.text('완성'));
    await _settle(tester);

    final ids = (await repository.listAll()).map((a) => a.id).toList();
    expect(ids.where((id) => id.startsWith('w1-복구-')), hasLength(1));
    expect(File('${root.path}/artworks/w1/artwork.json').readAsStringSync(),
        '{"id":"w1"', reason: '원본은 손대지 않는다');
  });

  test('작품 id 는 빠르게 두 번 만들어도 겹치지 않는다', () {
    final ids = {for (var i = 0; i < 50; i++) newArtworkId('flower-01')};
    expect(ids, hasLength(50));
    expect(ids.every((id) => id.startsWith('flower-01-')), isTrue);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/coloring_route_test.dart`
Expected: FAIL — `package:kkumul/coloring/coloring_route.dart` 가 없다는 컴파일 오류.

- [ ] **Step 3: `ColoringScreen` 에 `완성` 버튼을 붙인다**

`app/lib/ui/coloring_screen.dart` 의 `ColoringScreen` 에 필드를 더한다:

```dart
class ColoringScreen extends StatefulWidget {
  final ColoringController controller;

  /// 색칠을 마치고 나가는 길. 셸 위에 띄웠을 때만 준다.
  ///
  /// `null` 이면 `완성` 버튼을 보여주지 않는다 — 화면 하나만 띄우는
  /// 테스트가 그렇다.
  final Future<void> Function()? onFinish;

  const ColoringScreen({super.key, required this.controller, this.onFinish});
```

`build` 의 `AppBar.actions` 에서 `ShadeButton` **앞에** 완성 버튼을 넣는다:

```dart
        actions: [
          if (widget.onFinish != null)
            TextButton(
              key: const ValueKey('finish-button'),
              // 기본 TextButton 의 최소 높이는 36 이다. 스펙 10.3 의 64dp 를
              // 지키려면 직접 줘야 한다.
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 64),
                foregroundColor: const Color(0xFF246B4B),
                textStyle:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                unawaited(widget.onFinish!());
              },
              child: const Text('완성'),
            ),
          if (c.ageMode == AgeMode.child)
            ShadeButton(shade: c.shade, onCycle: c.cycleShade),
          // ... 되돌리기 버튼은 그대로
```

- [ ] **Step 4: `coloring_route.dart` 를 만든다**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/dohan_source.dart';
import '../gallery/artwork_repository.dart';
import '../gallery/autosave.dart';
import '../settings/settings.dart';
import '../ui/coloring_screen.dart';
import 'coloring_controller.dart';

/// 같은 밀리초 안에 두 번 만들어도 겹치지 않게 하는 카운터.
int _seq = 0;

/// 새 작품의 id. 도안 하나를 여러 번 칠할 수 있으므로 매번 새로 만든다.
///
/// 밀리초만 쓰면 아이가 도안을 빠르게 두 번 누를 때 같은 id 가 나와 두
/// 작품이 한 폴더를 공유한다 — 계획 3 의 스티커 instanceId 와 같은 함정이다.
String newArtworkId(String dohanId) =>
    '$dohanId-${DateTime.now().millisecondsSinceEpoch}-${_seq++}';

/// 셸이 탭에게 건네는 "색칠을 열어라". 아이가 나올 때까지 기다린다.
///
/// 탭은 `source`·`repository`·`ageMode` 를 몰라도 된다 — 그것들은 셸이
/// 쥐고 있고, 셸은 색칠이 끝나면 탭들에게 다시 읽으라고 알린다.
typedef OpenColoring = Future<void> Function({
  required String dohanId,
  required String artworkId,
});

/// 색칠 화면을 셸 위에 띄운다. 아이가 나올 때까지 기다린다.
///
/// 내비는 함께 올라가지 않는다(설계 스펙 2.1) — 320×640 에서 내비를 넣으면
/// 캔버스가 350 에서 286dp 로 줄어 본문의 절반 아래가 된다.
Future<void> openColoring(
  BuildContext context, {
  required DohanSource source,
  required ArtworkRepository repository,
  required AgeMode ageMode,
  required String dohanId,
  required String artworkId,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ColoringSession(
        source: source,
        repository: repository,
        ageMode: ageMode,
        dohanId: dohanId,
        artworkId: artworkId,
      ),
    ),
  );
}

/// 색칠 세션 하나의 생애를 쥔다.
///
/// 컨트롤러와 `Autosave` 를 **세션마다 새로** 만들고 pop 에서 버린다.
/// 돌려 쓰지 않는 이유는 두 가지다:
///
///  - `ColoringController.dispose()` 가 `autosave.dispose()` 를 부른다.
///    하나를 공유하면 첫 세션이 끝나는 순간 `_disposed` 가 서고, 그 뒤
///    `schedule()` 은 조용히 아무 일도 하지 않는다 — 두 번째 작품부터
///    아이가 칠한 것이 오류 없이 사라진다.
///  - 컨트롤러가 한 번만 `open()` 되므로 계획 2 후속 §1.1·§3.3 과
///    계획 3 후속 §1.1 이 **발생할 수 없게** 된다.
class ColoringSession extends StatefulWidget {
  final DohanSource source;
  final ArtworkRepository repository;
  final AgeMode ageMode;
  final String dohanId;
  final String artworkId;

  const ColoringSession({
    super.key,
    required this.source,
    required this.repository,
    required this.ageMode,
    required this.dohanId,
    required this.artworkId,
  });

  @override
  State<ColoringSession> createState() => _ColoringSessionState();
}

class _ColoringSessionState extends State<ColoringSession> {
  late final ColoringController _controller;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _controller = ColoringController(
      source: widget.source,
      autosave: Autosave(repository: widget.repository),
      ageMode: widget.ageMode,
    );
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _controller.open(
        dohanId: widget.dohanId,
        artworkId: widget.artworkId,
        existing: await widget.repository.load(widget.artworkId),
        stickers: await widget.repository.loadStickers(widget.artworkId),
        brushPng: await widget.repository.loadBrushPng(widget.artworkId),
      );
    } on Object catch (error) {
      // 읽기 자체가 실패했든(권한·잠김·디스크) 내용이 규칙을 어겼든, 아이가
      // 그 그림을 영영 못 여는 것이 가장 나쁜 결과다. 그렇다고 같은 id 로
      // 새로 시작하면 자동 저장이 잠깐 못 읽었을 뿐인 멀쩡한 파일 위에
      // 덮어쓴다. 복구용 id 로 비켜서 연다 — 아이는 계속 칠할 수 있고
      // 원본은 손대지 않는다.
      debugPrint('저장된 작품을 열지 못했습니다 — 새 작품으로 시작합니다: $error');
      await _controller.open(
        dohanId: widget.dohanId,
        artworkId: '${widget.artworkId}-복구-'
            '${DateTime.now().millisecondsSinceEpoch}',
      );
    }
    if (mounted) setState(() => _opened = true);
  }

  /// 나가는 길. `완성` 버튼과 기기 뒤로가기가 함께 쓴다.
  ///
  /// `close()` 를 **먼저 기다린다.** 그냥 pop 하면 화면이 먼저 사라져서
  /// 썸네일을 구울 텍스처가 이미 해제된 뒤가 된다.
  Future<void> _finish() async {
    await _controller.close();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_opened) {
      // 도안을 읽고 마스크를 만드는 동안이다. 아이에게는 한 박자지만
      // 빈 화면을 주면 눌러 볼 것이 없다.
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_finish());
      },
      child: ColoringScreen(controller: _controller, onFinish: _finish),
    );
  }
}
```

- [ ] **Step 5: 테스트를 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test test/coloring_route_test.dart`
Expected: PASS, 7개.

**교착하면**(타임아웃까지 아무 출력이 없으면) `_settle` 을 빠뜨린 자리를 찾는다. `openColoring` 뒤에는 언제나 `_settle` 이 와야 한다.

- [ ] **Step 6: 전부 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 198개 (191 + 7).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add app/lib/coloring/coloring_route.dart app/lib/ui/coloring_screen.dart app/test/coloring_route_test.dart
git commit -F - <<'GITEOF'
feat(app): 색칠을 세션으로 띄운다

컨트롤러와 Autosave 를 세션마다 새로 만들고 pop 에서 버린다.
ColoringController.dispose() 가 autosave 를 dispose 하므로 하나를
돌려 쓰면 두 번째 작품부터 저장이 조용히 멈춘다.

덤으로 후속 문서 세 항목이 발생할 수 없게 된다 — open() 이
컨트롤러당 한 번뿐이라 계획 2 후속 1.1/3.3 이 사라지고, 연령대는
다음에 열 때 새로 읽히므로 계획 3 후속 1.1 도 사라진다.

main() 의 -복구- 경로를 그대로 옮겨 왔다. 나가는 길은 완성 버튼과
기기 뒤로가기 둘 다 close() 를 먼저 기다린 뒤 pop 한다.
GITEOF
```

---
## Task 6: 격자 한 칸의 틀

놀기와 모아보기가 함께 쓰는 정사각 칸. **틀만** 맡는다 — 놀기의 칸은 도안의 선화를, 모아보기의 칸은 작품의 썸네일을 보여주므로 담는 것이 다르다. 공통인 것은 정사각 비율·모서리·터치 영역뿐이다.

**Files:**
- Create: `app/lib/ui/art_tile.dart`
- Create: `app/test/art_tile_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `const double kArtTileMinSize = 64`
  - `class ArtTile extends StatelessWidget` — `{required String label, required Widget child, required VoidCallback onTap}`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/art_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/ui/art_tile.dart';

void main() {
  testWidgets('정사각형이고 좁은 화면에서도 64dp 를 지킨다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 0; i < 4; i++)
              ArtTile(
                label: '칸 $i',
                onTap: () {},
                child: const ColoredBox(color: Colors.amber),
              ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    for (final e in find.byType(ArtTile).evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(kArtTileMinSize));
      expect(r.height, greaterThanOrEqualTo(kArtTileMinSize));
      expect(r.width, closeTo(r.height, 1.0), reason: '정사각이어야 한다');
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320),
          reason: '화면 밖으로 밀려난 칸은 아이에게 없는 칸이다');
    }
  });

  testWidgets('누르면 알려준다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 144,
            height: 144,
            child: ArtTile(
              label: '고양이',
              onTap: () => taps++,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(ArtTile));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('그림이 비어 있어도 누를 수 있다', (tester) async {
    // 썸네일이 아직 안 읽혔을 때다. 투명한 칸이 입력을 흘려보내면
    // 아이는 "눌리지 않는 그림"을 만난다.
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 144,
            height: 144,
            child: ArtTile(
              label: '빈 칸',
              onTap: () => taps++,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));

    await tester.tapAt(tester.getCenter(find.byType(ArtTile)));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('읽어 줄 이름을 단다', (tester) async {
    // 글을 못 읽는 아이를 위한 것이 아니라, 접근성 도구와 테스트가
    // 칸을 구분할 수 있게 하는 것이다.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 144,
            height: 144,
            child: ArtTile(
              label: '고양이',
              onTap: () {},
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));

    expect(find.bySemanticsLabel('고양이'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/art_tile_test.dart`
Expected: FAIL — `package:kkumul/ui/art_tile.dart` 가 없다.

- [ ] **Step 3: 구현한다**

`app/lib/ui/art_tile.dart`:

```dart
import 'package:flutter/material.dart';

/// 격자 한 칸의 최소 변. 상위 스펙 10.3 의 터치 타겟이다.
const double kArtTileMinSize = 64;

/// 놀기와 모아보기가 함께 쓰는 격자 칸의 **틀**.
///
/// 담는 것은 서로 다르다 — 놀기는 도안의 선화를, 모아보기는 작품의
/// 썸네일(없으면 선화)을 보여준다. 하나의 "도안 타일"로 합치면 둘 중
/// 하나에 안 맞는 인자가 생기므로, 공통인 정사각 비율·모서리·터치 영역만
/// 여기서 맡고 그림은 [child] 로 받는다.
class ArtTile extends StatelessWidget {
  /// 접근성 도구와 테스트가 칸을 구분할 이름.
  final String label;

  final Widget child;
  final VoidCallback onTap;

  const ArtTile({
    super.key,
    required this.label,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        // 썸네일이 아직 안 읽혔으면 칸 속이 비어 있다. opaque 가 없으면
        // 그 칸은 입력을 흘려보내 "눌리지 않는 그림"이 된다.
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kArtTileMinSize,
            minHeight: kArtTileMinSize,
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD8DCD8), width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 테스트를 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 202개 (198 + 4).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app/lib/ui/art_tile.dart app/test/art_tile_test.dart
git commit -F - <<'GITEOF'
feat(app): 격자 한 칸의 틀

놀기와 모아보기가 함께 쓴다. 담는 것이 서로 달라서 틀만 공유하고
그림은 각자 넣는다. 속이 비어 있어도 눌리도록 히트 테스트를
opaque 로 둔다 — 썸네일을 읽는 동안이 그렇다.
GITEOF
```

---

## Task 7: 모아보기

내 작품을 최신순 2열 격자로. 작품을 누르면 **이어 그리기**로 연다. 작품별 삭제는 넣지 않는다(설계 스펙 3절) — 아이에게 영구 삭제는 되돌릴 수 없고, 글을 못 읽으니 확인 대화상자도 작동하지 않는다.

**Files:**
- Create: `app/lib/gallery/gallery_screen.dart`
- Create: `app/test/gallery_screen_test.dart`

**Interfaces:**
- Consumes: `ArtworkRepository.listAll` · `ArtworkRepository.loadThumbnail` (태스크 3) · `ArtTile` (태스크 6) · `OpenColoring` (태스크 5)
- Produces: `class GalleryScreen extends StatefulWidget` — `{required ArtworkRepository repository, required OpenColoring onOpen, int refreshToken = 0}`

`refreshToken` 은 셸이 색칠에서 돌아올 때마다 올려 주는 숫자다. 바뀌면 다시 읽는다 — 탭이 `IndexedStack` 안에 살아 있어서 스스로는 다시 지어지지 않기 때문이다(태스크 11).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/gallery_screen_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_route.dart' show OpenColoring;
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/gallery/gallery_screen.dart';
import 'package:kkumul/ui/art_tile.dart';

/// 진짜 빨강 PNG. 썸네일이 실제로 화면에 올라오는지 보려면 디코딩되는
/// 이미지여야 한다 — 바이트를 손으로 적지 말고 만들어 쓴다.
Uint8List _redPng() {
  final im = img.Image(width: 8, height: 8, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  late Directory root;
  late ArtworkRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_gallery_');
    repository = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> addArtwork(String id, {required DateTime at}) =>
      repository.save(Artwork(
        id: id,
        dohanId: 'flower-01',
        fills: const {2: 0xFFFF0000},
        updatedAt: at,
      ));

  Widget host({int refreshToken = 0, OpenColoring? onOpen}) => MaterialApp(
        home: Scaffold(
          body: GalleryScreen(
            repository: repository,
            refreshToken: refreshToken,
            onOpen: onOpen ??
                ({required String dohanId, required String artworkId}) async {},
          ),
        ),
      );

  /// 썸네일 PNG 디코딩은 엔진 콜백이다. 실제 존에서 한 박자 돌린다.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  testWidgets('작품이 없으면 빈 상태 안내를 보여준다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.byKey(const ValueKey('gallery-empty')), findsOneWidget);
    expect(find.byType(ArtTile), findsNothing);
  });

  testWidgets('작품을 최신순으로 보여준다', (tester) async {
    await addArtwork('old', at: DateTime.utc(2026, 10, 1));
    await addArtwork('new', at: DateTime.utc(2026, 10, 5));

    await tester.pumpWidget(host());
    await settle(tester);

    final tiles = find.byType(ArtTile);
    expect(tiles, findsNWidgets(2));
    expect(find.byKey(const ValueKey('gallery-empty')), findsNothing);

    final first = tester.widget<ArtTile>(tiles.first);
    expect(first.label, contains('new'), reason: '최근에 고친 것이 먼저다');
  });

  testWidgets('썸네일이 있으면 그것을, 없으면 선화를 보여준다', (tester) async {
    await addArtwork('withThumb', at: DateTime.utc(2026, 10, 5));
    await addArtwork('noThumb', at: DateTime.utc(2026, 10, 1));
    await repository.saveThumbnail('withThumb', _redPng());

    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byKey(const ValueKey('thumb-withThumb')), findsOneWidget);
    expect(find.byKey(const ValueKey('lineart-noThumb')), findsOneWidget,
        reason: '강제 종료로 썸네일을 못 구운 경우가 정상 경로에 있다');
  });

  testWidgets('작품을 누르면 그 작품을 이어서 연다', (tester) async {
    await addArtwork('w1', at: DateTime.utc(2026, 10, 5));
    String? openedArtwork;
    String? openedDohan;

    await tester.pumpWidget(host(
      onOpen: ({required String dohanId, required String artworkId}) async {
        openedDohan = dohanId;
        openedArtwork = artworkId;
      },
    ));
    await settle(tester);

    await tester.tap(find.byType(ArtTile));
    await settle(tester);

    expect(openedArtwork, 'w1', reason: '새 작품이 아니라 그 작품을 이어 그린다');
    expect(openedDohan, 'flower-01');
  });

  testWidgets('refreshToken 이 바뀌면 다시 읽는다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);
    expect(find.byType(ArtTile), findsNothing);

    await addArtwork('w1', at: DateTime.utc(2026, 10, 5));
    await tester.pumpWidget(host(refreshToken: 1));
    await settle(tester);

    expect(find.byType(ArtTile), findsOneWidget,
        reason: '색칠에서 돌아왔는데 새 작품이 안 보이면 안 된다');
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/gallery_screen_test.dart`
Expected: FAIL — `package:kkumul/gallery/gallery_screen.dart` 가 없다.

- [ ] **Step 3: 구현한다**

`app/lib/gallery/gallery_screen.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../coloring/coloring_route.dart' show OpenColoring;
import '../core/artwork.dart';
import '../ui/art_tile.dart';
import 'artwork_repository.dart';

/// 내 작품을 모아 본다. 누르면 이어 그린다.
///
/// 작품별 삭제는 두지 않는다(설계 스펙 3절). 아이에게 영구 삭제는 되돌릴
/// 수 없고, 글을 못 읽으니 확인 대화상자도 작동하지 않는다. 정리는 글을
/// 읽는 사람이 쓰는 `내 정보` 에서 한다.
class GalleryScreen extends StatefulWidget {
  final ArtworkRepository repository;
  final OpenColoring onOpen;

  /// 셸이 색칠에서 돌아올 때마다 올려 주는 숫자. 바뀌면 다시 읽는다.
  ///
  /// 탭이 `IndexedStack` 안에 살아 있어서 스스로는 다시 지어지지 않는다 —
  /// 이것이 없으면 놀기에서 그린 그림이 모아보기에 영영 안 나타난다.
  final int refreshToken;

  const GalleryScreen({
    super.key,
    required this.repository,
    required this.onOpen,
    this.refreshToken = 0,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  /// `null` 이면 아직 읽는 중이다. 빈 목록과 구별해야 빈 상태 안내가
  /// 읽는 동안 잠깐 번쩍이지 않는다.
  List<Artwork>? _artworks;
  Map<String, Uint8List> _thumbs = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(GalleryScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) unawaited(_load());
  }

  Future<void> _load() async {
    final list = await widget.repository.listAll();
    final thumbs = <String, Uint8List>{};
    for (final a in list) {
      final png = await widget.repository.loadThumbnail(a.id);
      if (png != null) thumbs[a.id] = png;
    }
    if (!mounted) return;
    setState(() {
      _artworks = list;
      _thumbs = thumbs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final artworks = _artworks;
    if (artworks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (artworks.isEmpty) return const _EmptyGallery();

    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(12),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final a in artworks)
          ArtTile(
            label: '내 그림 ${a.id}',
            onTap: () =>
                widget.onOpen(dohanId: a.dohanId, artworkId: a.id),
            child: _thumbnailFor(a),
          ),
      ],
    );
  }

  /// 썸네일이 있으면 그것을, 없으면 그 도안의 선화를 보여준다.
  ///
  /// 썸네일이 없는 것은 앱이 강제 종료되어 `close()` 가 못 돈 경우다.
  /// 선화는 에셋으로 항상 있고, 아이는 그림 모양으로 자기 작품을
  /// 알아본다 — 색이 없을 뿐이다. 다음에 그 작품을 열고 나가면 생긴다.
  Widget _thumbnailFor(Artwork a) {
    final png = _thumbs[a.id];
    if (png != null) {
      return Image.memory(
        png,
        key: ValueKey('thumb-${a.id}'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Image.asset(
      'assets/dohans/${a.dohanId}/lineart.png',
      key: ValueKey('lineart-${a.id}'),
      fit: BoxFit.cover,
      // 도안이 사라진 작품(앱을 업데이트하며 도안을 뺀 경우)이라도
      // 칸은 남아야 한다. 누르면 색칠 쪽에서 제대로 알려 준다.
      errorBuilder: (_, __, ___) =>
          const ColoredBox(color: Color(0xFFF2F2EE)),
    );
  }
}

/// 작품이 하나도 없을 때. 상위 스펙 10.2 의 필수 요소다.
class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('gallery-empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 글을 못 읽는 아이에게는 이 그림이 문구보다 많이 말한다.
          const Icon(Icons.palette_outlined,
              size: 96, color: Color(0xFFB7BFB8)),
          const SizedBox(height: 16),
          Text(
            '아직 그린 그림이 없어요',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('놀기에서 그림을 골라 보세요',
              style: TextStyle(color: Color(0xFF6B736C))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 테스트를 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 207개 (202 + 5).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app/lib/gallery/gallery_screen.dart app/test/gallery_screen_test.dart
git commit -F - <<'GITEOF'
feat(app): 모아보기

최신순 2열 격자. 누르면 그 작품을 이어 그린다. 썸네일이 없으면
그 도안의 선화로 대체한다 — 강제 종료로 못 구운 경우가 정상
경로에 있고, 아이는 색이 없어도 그림 모양으로 알아본다.

작품별 삭제는 넣지 않는다. refreshToken 으로 다시 읽는 것은
탭이 IndexedStack 안에 살아 있어서 스스로 다시 지어지지 않기
때문이다.
GITEOF
```

---
## Task 8: 놀기

가장 빠른 시작(상위 스펙 10.2). 위에서 아래로 **이어 그리기 → 오늘의 도안 → 카테고리별 도안**.

**가로 스크롤 줄을 쓰지 않는다.** 계획 3 최종 리뷰가 잡은 결함이 정확히 그것이다 — 가로로 밀리는 줄은 글을 못 읽는 아이에게 "없는 것"이다. 전부 세로 스크롤 안의 2열 격자로 펼친다.

도안 열두 장의 **카테고리만** 알면 되는데 `DohanSource.load` 는 1024² PNG 두 장을 디코딩한다. 열두 번 하면 화면 하나 여는 데 그 비용을 다 낸다 — `loadMeta` 를 더한다.

**Files:**
- Create: `app/lib/play/play_screen.dart`
- Create: `app/test/play_screen_test.dart`
- Modify: `app/lib/core/dohan_source.dart`
- Modify: `app/lib/library/bundled_dohan_source.dart`
- Modify: `app/test/coloring_controller_test.dart` (`FakeDohanSource` 에 `loadMeta`)
- Modify: `app/test/coloring_screen_test.dart` (`FakeDohanSource` 에 `loadMeta`)
- Modify: `app/test/coloring_route_test.dart` (`FakeDohanSource` 에 `loadMeta`)
- Test: `app/test/bundled_dohan_source_test.dart`

**Interfaces:**
- Consumes: `ArtTile` (태스크 6) · `OpenColoring`·`newArtworkId` (태스크 5) · `ArtworkRepository.listAll` · `BundledDohanSource.defaultIds` (태스크 2)
- Produces:
  - `Future<DohanMeta> DohanSource.loadMeta(String id)`
  - `class PlayScreen extends StatefulWidget` — `{required DohanSource source, required ArtworkRepository repository, required OpenColoring onOpen, int refreshToken = 0, DateTime? today}`

`today` 는 테스트용이다. 주지 않으면 지금 날짜를 쓴다.

- [ ] **Step 1: `DohanSource` 에 `loadMeta` 를 더하고 구현체 넷을 맞춘다**

`app/lib/core/dohan_source.dart`:

```dart
abstract class DohanSource {
  /// 이 소스가 가진 도안 ID 목록.
  Future<List<String>> listIds();

  /// 도안 한 벌을 읽는다. 없는 ID 면 [ArgumentError] 를 던진다.
  Future<DohanPackage> load(String id);

  /// 메타데이터만 읽는다. 없는 ID 면 [ArgumentError] 를 던진다.
  ///
  /// `놀기` 는 열두 장의 카테고리와 제목만 있으면 되는데, [load] 는 1024²
  /// PNG 두 장을 디코딩한다. 화면 하나 여는 데 그 비용을 열두 번 낼 이유가
  /// 없다.
  Future<DohanMeta> loadMeta(String id);
}
```

`app/lib/library/bundled_dohan_source.dart` 의 `load` 아래에 더한다:

```dart
  @override
  Future<DohanMeta> loadMeta(String id) async {
    if (!_ids.contains(id)) {
      throw ArgumentError('내장 도안에 없는 ID 입니다: $id');
    }
    final dir = 'assets/dohans/$id';
    final meta = await _bundle.load('$dir/meta.json');
    // ByteData 는 더 큰 버퍼의 조각일 수 있다 — load() 와 같은 이유로
    // .buffer 가 아니라 sublistView 를 쓴다.
    return DohanMeta.parse(
      utf8.decode(Uint8List.sublistView(meta)),
      label: dir,
    );
  }
```

테스트 파일 셋(`coloring_controller_test.dart` · `coloring_screen_test.dart` · `coloring_route_test.dart`)의 `FakeDohanSource` 에 똑같이 더한다. 각 파일의 `load` 가 만드는 `DohanMeta` 와 같은 것을 돌려주면 된다 — 가장 간단한 방법:

```dart
  @override
  Future<DohanMeta> loadMeta(String id) async => (await load(id)).meta;
```

- [ ] **Step 2: `loadMeta` 테스트를 쓰고 돌린다**

`app/test/bundled_dohan_source_test.dart` 에 붙인다:

```dart
  test('메타만 읽으면 선화를 디코딩하지 않는다', () async {
    final source = BundledDohanSource();

    final meta = await source.loadMeta('flower-01');

    expect(meta.id, 'flower-01');
    expect(meta.title, '동그라미 꽃');
    expect(meta.category, 'shape');
  });

  test('없는 도안의 메타를 읽으면 한국어로 알려준다', () async {
    expect(
      () => BundledDohanSource().loadMeta('없는도안'),
      throwsA(isA<ArgumentError>()
          .having((e) => e.message, 'message', contains('없는도안'))),
    );
  });
```

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 209개 (207 + 2).

- [ ] **Step 3: 놀기 테스트를 쓴다**

`app/test/play_screen_test.dart`:

```dart
import 'dart:io';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_route.dart' show OpenColoring;
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/play/play_screen.dart';
import 'package:kkumul/ui/art_tile.dart';

/// 카테고리 넷에 셋씩, 실제 라이브러리와 같은 모양의 가짜 소스.
///
/// `load` 는 부르지 않는다 — 놀기는 `loadMeta` 만 쓴다. 불리면 테스트가
/// 실패하도록 던져 둔다.
class FakeLibrary implements DohanSource {
  static const _ids = [
    'animal-a', 'animal-b', 'animal-c', //
    'car-a', 'car-b', 'car-c',
    'dino-a', 'dino-b', 'dino-c',
    'shape-a', 'shape-b', 'shape-c',
  ];

  @override
  Future<List<String>> listIds() async => _ids;

  @override
  Future<DohanPackage> load(String id) async =>
      throw StateError('놀기가 도안 전체를 읽으면 안 된다: $id');

  @override
  Future<DohanMeta> loadMeta(String id) async => DohanMeta(
        id: id,
        title: '제목 $id',
        category: id.split('-').first == 'dino'
            ? 'dinosaur'
            : id.split('-').first,
        source: 'bundled',
        canvasSize: const [1024, 1024],
        regionCount: 4,
        difficulty: 1,
        suggestedPalette: const [],
        regionAnchors: const {},
        createdAt: DateTime.utc(2026, 10, 6),
      );
}

void main() {
  late Directory root;
  late ArtworkRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_play_');
    repository = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Widget host({
    OpenColoring? onOpen,
    DateTime? today,
    int refreshToken = 0,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: PlayScreen(
            source: FakeLibrary(),
            repository: repository,
            today: today,
            refreshToken: refreshToken,
            onOpen: onOpen ??
                ({required String dohanId, required String artworkId}) async {},
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  testWidgets('카테고리 넷을 제목과 함께 세로로 펼친다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    for (final name in ['동물', '자동차', '공룡', '모양']) {
      expect(find.text(name), findsOneWidget, reason: '$name 제목이 없다');
    }

    // 가로로 밀리는 줄이 하나도 없어야 한다. 글을 못 읽는 아이에게
    // 가로 스크롤은 "없는 것"이다.
    for (final e in find.byType(Scrollable).evaluate()) {
      final s = e.widget as Scrollable;
      expect(s.axisDirection, isNot(AxisDirection.right));
      expect(s.axisDirection, isNot(AxisDirection.left));
    }
  });

  testWidgets('오늘의 도안은 하루 동안 같고 날이 바뀌면 바뀐다', (tester) async {
    await tester.pumpWidget(host(today: DateTime.utc(2026, 10, 6)));
    await settle(tester);
    final first =
        tester.widget<ArtTile>(find.byKey(const ValueKey('today-tile'))).label;

    await tester.pumpWidget(host(today: DateTime.utc(2026, 10, 6, 23, 59)));
    await settle(tester);
    expect(
      tester.widget<ArtTile>(find.byKey(const ValueKey('today-tile'))).label,
      first,
      reason: '같은 날에는 같은 도안이어야 한다',
    );

    // 열두 장이므로 열사흘 안에 반드시 다른 것이 나온다.
    final later = <String>{};
    for (var d = 1; d <= 13; d++) {
      await tester.pumpWidget(host(today: DateTime.utc(2026, 10, 6 + d)));
      await settle(tester);
      later.add(tester
          .widget<ArtTile>(find.byKey(const ValueKey('today-tile')))
          .label);
    }
    expect(later.any((l) => l != first), isTrue, reason: '내일은 달라야 한다');
  });

  testWidgets('도안을 누르면 새 작품으로 연다', (tester) async {
    String? openedDohan;
    String? openedArtwork;

    await tester.pumpWidget(host(
      onOpen: ({required String dohanId, required String artworkId}) async {
        openedDohan = dohanId;
        openedArtwork = artworkId;
      },
    ));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('today-tile')));
    await settle(tester);

    expect(openedDohan, isNotNull);
    expect(openedArtwork, startsWith('$openedDohan-'),
        reason: '놀기는 언제나 새 작품으로 시작한다');
  });

  testWidgets('작품이 없으면 이어 그리기 칸을 통째로 뺀다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.byKey(const ValueKey('continue-tile')), findsNothing);
    expect(find.text('이어 그리기'), findsNothing);
  });

  testWidgets('이어 그리기는 가장 최근 작품을 그대로 연다', (tester) async {
    await repository.save(Artwork(
      id: 'old',
      dohanId: 'animal-a',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 1),
    ));
    await repository.save(Artwork(
      id: 'recent',
      dohanId: 'car-b',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 5),
    ));
    String? openedArtwork;

    await tester.pumpWidget(host(
      onOpen: ({required String dohanId, required String artworkId}) async {
        openedArtwork = artworkId;
      },
    ));
    await settle(tester);

    expect(find.text('이어 그리기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('continue-tile')));
    await settle(tester);

    expect(openedArtwork, 'recent', reason: '새 작품이 아니라 그 작품을 잇는다');
  });

  testWidgets('refreshToken 이 바뀌면 이어 그리기를 다시 읽는다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);
    expect(find.text('이어 그리기'), findsNothing);

    await repository.save(Artwork(
      id: 'w1',
      dohanId: 'animal-a',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 5),
    ));
    await tester.pumpWidget(host(refreshToken: 1));
    await settle(tester);

    expect(find.text('이어 그리기'), findsOneWidget);
  });
}
```

- [ ] **Step 4: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/play_screen_test.dart`
Expected: FAIL — `package:kkumul/play/play_screen.dart` 가 없다.

- [ ] **Step 5: 구현한다**

`app/lib/play/play_screen.dart`:

```dart
import 'dart:async';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';

import '../coloring/coloring_route.dart' show OpenColoring, newArtworkId;
import '../core/artwork.dart';
import '../core/dohan_source.dart';
import '../gallery/artwork_repository.dart';
import '../ui/art_tile.dart';

/// 카테고리 코드와 아이에게 보여줄 이름. 순서가 화면 순서다.
const _categories = <(String, String)>[
  ('animal', '동물'),
  ('car', '자동차'),
  ('dinosaur', '공룡'),
  ('shape', '모양'),
];

/// 도안을 고르는 화면. 상위 스펙 10.2 의 "가장 빠른 시작".
///
/// 위에서 아래로 이어 그리기 → 오늘의 도안 → 카테고리별 도안.
/// 전부 세로 스크롤 안이다 — 가로로 밀리는 줄은 글을 못 읽는 아이에게
/// 없는 것과 같다(계획 3 최종 리뷰).
class PlayScreen extends StatefulWidget {
  final DohanSource source;
  final ArtworkRepository repository;
  final OpenColoring onOpen;

  /// 셸이 색칠에서 돌아올 때마다 올려 주는 숫자. 바뀌면 다시 읽는다.
  final int refreshToken;

  /// 오늘의 도안을 고르는 기준 날짜. 테스트용이고, 주지 않으면 지금이다.
  final DateTime? today;

  const PlayScreen({
    super.key,
    required this.source,
    required this.repository,
    required this.onOpen,
    this.refreshToken = 0,
    this.today,
  });

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  List<DohanMeta>? _metas;
  Artwork? _recent;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PlayScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) unawaited(_loadRecent());
  }

  Future<void> _load() async {
    final ids = await widget.source.listIds();
    final metas = <DohanMeta>[];
    for (final id in ids) {
      metas.add(await widget.source.loadMeta(id));
    }
    if (!mounted) return;
    setState(() => _metas = metas);
    await _loadRecent();
  }

  Future<void> _loadRecent() async {
    // listAll 이 updatedAt 역순으로 준다.
    final all = await widget.repository.listAll();
    if (!mounted) return;
    setState(() => _recent = all.isEmpty ? null : all.first);
  }

  /// 오늘의 도안. 날짜를 씨앗으로 고르므로 하루 종일 같고 내일 바뀐다.
  ///
  /// 난수 상태를 저장할 필요가 없다는 것이 이 방식의 전부다.
  DohanMeta _todayDohan(List<DohanMeta> metas) {
    final now = (widget.today ?? DateTime.now()).toUtc();
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(1970))
        .inDays;
    return metas[days % metas.length];
  }

  void _openNew(DohanMeta meta) {
    widget.onOpen(dohanId: meta.id, artworkId: newArtworkId(meta.id));
  }

  @override
  Widget build(BuildContext context) {
    final metas = _metas;
    if (metas == null || metas.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final recent = _recent;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (recent != null) ...[
          const _Heading('이어 그리기'),
          ArtTile(
            key: const ValueKey('continue-tile'),
            label: '이어 그리기 ${recent.id}',
            onTap: () => widget.onOpen(
              dohanId: recent.dohanId,
              artworkId: recent.id,
            ),
            child: _lineart(recent.dohanId),
          ),
          const SizedBox(height: 16),
        ],
        const _Heading('오늘의 그림'),
        Builder(builder: (_) {
          final today = _todayDohan(metas);
          return ArtTile(
            key: const ValueKey('today-tile'),
            label: today.title,
            onTap: () => _openNew(today),
            child: _lineart(today.id),
          );
        }),
        for (final (code, name) in _categories) ...[
          const SizedBox(height: 16),
          _Heading(name),
          _Grid(
            metas: [for (final m in metas) if (m.category == code) m],
            onPick: _openNew,
            lineart: _lineart,
          ),
        ],
      ],
    );
  }

  Widget _lineart(String dohanId) => Image.asset(
        'assets/dohans/$dohanId/lineart.png',
        fit: BoxFit.cover,
        // 테스트의 가짜 라이브러리처럼 에셋이 없을 수 있다. 칸 자체는
        // 남아야 아이가 누를 곳을 잃지 않는다.
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFF2F2EE)),
      );
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// 한 카테고리의 도안들. 스스로 스크롤하지 않고 바깥 목록에 실린다.
class _Grid extends StatelessWidget {
  final List<DohanMeta> metas;
  final void Function(DohanMeta) onPick;
  final Widget Function(String) lineart;

  const _Grid({
    required this.metas,
    required this.onPick,
    required this.lineart,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final m in metas)
          ArtTile(
            label: m.title,
            onTap: () => onPick(m),
            child: lineart(m.id),
          ),
      ],
    );
  }
}
```

- [ ] **Step 6: 전부 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 215개 (209 + 6).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add app/lib/play app/lib/core/dohan_source.dart app/lib/library app/test
git commit -F - <<'GITEOF'
feat(app): 놀기

이어 그리기 - 오늘의 그림 - 카테고리별 도안. 전부 세로 스크롤
안의 2열 격자다. 가로로 밀리는 줄은 글을 못 읽는 아이에게 없는
것과 같다 - 계획 3 최종 리뷰가 잡은 결함이 그것이었다.

오늘의 그림은 날짜를 씨앗으로 고른다. 난수 상태를 저장할 필요가
없다.

DohanSource 에 loadMeta 를 더했다. 카테고리만 알면 되는데 load 는
1024 제곱 PNG 두 장을 디코딩한다 - 열두 번이면 화면 하나 여는 데
그 비용을 다 낸다.
GITEOF
```

---

## Task 9: 내 정보

유일하게 **어른이 읽는 화면**이라 글을 써도 된다. 연령대와 데이터 초기화 둘뿐이다 — 닉네임·공개 범위·음소거는 소비자가 아직 없어 넣지 않는다(설계 스펙 1절).

**Files:**
- Create: `app/lib/settings/settings_screen.dart`
- Create: `app/test/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsStore`·`Settings`·`AgeMode` · `ArtworkRepository.deleteAll` (태스크 3)
- Produces: `class SettingsScreen extends StatefulWidget` — `{required SettingsStore store, required ArtworkRepository repository, required AgeMode ageMode, required ValueChanged<AgeMode> onAgeModeChanged, VoidCallback? onDataCleared}`

연령대는 셸이 쥐고 있으므로 화면은 **고른 것을 알려만 준다.** 저장은 화면이 한다(`SettingsStore.save`).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/settings_screen_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/settings/settings.dart';
import 'package:kkumul/settings/settings_screen.dart';

void main() {
  late Directory root;
  late ArtworkRepository repository;
  late SettingsStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_settings_');
    repository = ArtworkRepository(root);
    store = SettingsStore(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Widget host({
    AgeMode ageMode = AgeMode.toddler,
    ValueChanged<AgeMode>? onChanged,
    VoidCallback? onCleared,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            store: store,
            repository: repository,
            ageMode: ageMode,
            onAgeModeChanged: onChanged ?? (_) {},
            onDataCleared: onCleared,
          ),
        ),
      );

  testWidgets('연령대를 고르면 알려주고 저장한다', (tester) async {
    AgeMode? picked;
    await tester.pumpWidget(host(onChanged: (m) => picked = m));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('age-child')));
    await tester.pumpAndSettle();

    expect(picked, AgeMode.child);
    expect((await store.load()).ageMode, AgeMode.child);
  });

  testWidgets('데이터 초기화는 두 단계를 거친다', (tester) async {
    await repository.save(Artwork(
      id: 'w1',
      dohanId: 'flower-01',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 6),
    ));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clear-data')));
    await tester.pumpAndSettle();

    // 1단계: 아직 아무것도 지워지지 않았다
    expect(await repository.listAll(), hasLength(1));
    expect(find.byKey(const ValueKey('clear-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-confirm')));
    await tester.pumpAndSettle();

    expect(await repository.listAll(), isEmpty);
  });

  testWidgets('확인에서 취소하면 아무것도 지워지지 않는다', (tester) async {
    await repository.save(Artwork(
      id: 'w1',
      dohanId: 'flower-01',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 6),
    ));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clear-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-cancel')));
    await tester.pumpAndSettle();

    expect(await repository.listAll(), hasLength(1));
    expect(find.byKey(const ValueKey('clear-confirm')), findsNothing);
  });

  testWidgets('지운 뒤 셸에 알려준다', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(host(onCleared: () => cleared++));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clear-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-confirm')));
    await tester.pumpAndSettle();

    expect(cleared, 1, reason: '모아보기가 빈 것을 알아야 한다');
  });

  testWidgets('연령대 버튼도 64dp 를 지킨다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    for (final key in ['age-toddler', 'age-child']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.height, greaterThanOrEqualTo(64));
    }
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/settings_screen_test.dart`
Expected: FAIL — `package:kkumul/settings/settings_screen.dart` 가 없다.

- [ ] **Step 3: 구현한다**

`app/lib/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../gallery/artwork_repository.dart';
import 'settings.dart';

/// 보호자가 보는 화면. 이 앱에서 **유일하게 어른이 읽는 자리**라 글을 써도
/// 된다.
///
/// 닉네임·공개 범위·음소거는 넣지 않는다. 랭크와 공유와 효과음이 아직
/// 없어서, 지금 만들면 아무것도 하지 않는 스위치가 된다(설계 스펙 1절).
class SettingsScreen extends StatefulWidget {
  final SettingsStore store;
  final ArtworkRepository repository;

  /// 셸이 쥐고 있는 현재 값.
  final AgeMode ageMode;

  /// 아이가 다음에 색칠을 열 때 이 값이 쓰인다.
  final ValueChanged<AgeMode> onAgeModeChanged;

  /// 작품을 다 지운 뒤. 모아보기와 놀기가 다시 읽어야 한다.
  final VoidCallback? onDataCleared;

  const SettingsScreen({
    super.key,
    required this.store,
    required this.repository,
    required this.ageMode,
    required this.onAgeModeChanged,
    this.onDataCleared,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _pick(AgeMode mode) async {
    if (mode == widget.ageMode) return;
    widget.onAgeModeChanged(mode);
    await widget.store.save(Settings(ageMode: mode));
  }

  /// 되돌릴 수 없으므로 두 단계를 거친다. 작품별 삭제가 없으므로 정리
  /// 수단은 이것뿐이고, 그만큼 실수로 눌리면 안 된다.
  Future<void> _clearData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모든 그림을 지울까요?'),
        content: const Text(
          '아이가 그린 그림이 모두 사라지고 되돌릴 수 없습니다.\n'
          '연령대 설정은 그대로 남습니다.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('clear-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            key: const ValueKey('clear-confirm'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFC6172F)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await widget.repository.deleteAll();
    widget.onDataCleared?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('내 정보', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        Text('연령대', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          '유아는 색 채우기 하나로 단순하게, 아동은 크레용·붓·지우개·'
          '스티커까지 모두 씁니다.',
          style: TextStyle(color: Color(0xFF6B736C)),
        ),
        const SizedBox(height: 12),
        _AgeChoice(
          buttonKey: const ValueKey('age-toddler'),
          title: '유아 (3~5세)',
          selected: widget.ageMode == AgeMode.toddler,
          onTap: () => _pick(AgeMode.toddler),
        ),
        const SizedBox(height: 8),
        _AgeChoice(
          buttonKey: const ValueKey('age-child'),
          title: '아동 (6~9세)',
          selected: widget.ageMode == AgeMode.child,
          onTap: () => _pick(AgeMode.child),
        ),
        const SizedBox(height: 32),
        Text('데이터', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          '그림은 이 기기에만 저장됩니다. 하나씩 지우는 기능은 없습니다 — '
          '아이가 실수로 지우는 일을 막기 위해서입니다.',
          style: TextStyle(color: Color(0xFF6B736C)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('clear-data'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            foregroundColor: const Color(0xFFC6172F),
          ),
          onPressed: _clearData,
          child: const Text('모든 그림 지우기'),
        ),
      ],
    );
  }
}

class _AgeChoice extends StatelessWidget {
  final Key buttonKey;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _AgeChoice({
    required this.buttonKey,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: buttonKey,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        backgroundColor:
            selected ? const Color(0xFFE6EFE9) : Colors.transparent,
        side: BorderSide(
          color: selected ? const Color(0xFF246B4B) : const Color(0xFFD8DCD8),
          width: 3,
        ),
        foregroundColor: const Color(0xFF1C1F1D),
      ),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? const Color(0xFF246B4B) : const Color(0xFF6B736C),
          ),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 전부 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 220개 (215 + 5).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app/lib/settings/settings_screen.dart app/test/settings_screen_test.dart
git commit -F - <<'GITEOF'
feat(app): 내 정보

연령대와 데이터 초기화 둘뿐이다. 닉네임과 공개 범위와 음소거는
소비자가 아직 없어 넣지 않는다 - 아무것도 하지 않는 스위치가 된다.

이 화면이 계획 3 후속 1.1 의 지뢰를 실제로 해체한다. 설정을 바꿀 때
색칠 화면은 존재하지 않고, 다음에 열면 새 컨트롤러가 현재 값을 읽는다.

데이터 초기화는 되돌릴 수 없으므로 두 단계를 거친다. 작품별 삭제가
없으므로 정리 수단은 이것뿐이고, 그만큼 실수로 눌리면 안 된다.
GITEOF
```

---
## Task 10: 다섯 칸 내비

`놀기 · 모아보기 · ＋만들기 · 랭크 · 내 정보`. `만들기` 와 `랭크` 는 아직 없지만 **칸은 지금 만든다** — 상위 스펙 10.1 이 `만들기` 를 "중앙의 큰 더하기 버튼으로 분리"하라고 해서, 그 버튼이 위젯의 구조 자체를 바꾼다. 나중에 끼워 넣으면 위젯을 다시 짜고 64dp 기하도 다시 재야 한다.

**폭 예산에 여유가 0 이다**: 다섯 칸 × 64dp = 정확히 320dp. 계획 3 의 도구 줄과 같은 주의가 필요하다.

**Files:**
- Create: `app/lib/shell/bottom_nav.dart`
- Create: `app/test/bottom_nav_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum ShellTab { play, gallery, create, rank, me }`
  - `const double kNavHeight = 64`
  - `class BottomNav extends StatelessWidget` — `{required ShellTab selected, required ValueChanged<ShellTab> onSelect}`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/bottom_nav_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/shell/bottom_nav.dart';

void main() {
  Widget host({
    ShellTab selected = ShellTab.play,
    ValueChanged<ShellTab>? onSelect,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar:
              BottomNav(selected: selected, onSelect: onSelect ?? (_) {}),
        ),
      );

  testWidgets('좁은 화면에서 다섯 칸이 64dp 를 지키고 제스처 영역을 피한다',
      (tester) async {
    // 다섯 칸 x 64dp = 정확히 320dp. 여유가 0 이라 한 픽셀만 어긋나도
    // 칸이 화면 밖으로 밀리거나 터치 타겟이 깎인다.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final slots = find.byType(NavSlot);
    expect(slots, findsNWidgets(5));

    for (final e in slots.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320),
          reason: '화면 밖으로 밀려난 칸은 아이에게 없는 칸이다');
      expect(r.bottom, lessThanOrEqualTo(640 - 34),
          reason: '제스처 영역에 걸치면 탭 대신 홈 제스처가 먹는다');
    }
  });

  testWidgets('아이콘과 한글 라벨을 함께 보여준다', (tester) async {
    // 상위 스펙 10.1 — 색만으로 의미를 전달하지 않는다.
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    for (final label in ['놀기', '모아보기', '만들기', '랭크', '내 정보']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(Icon), findsNWidgets(5));
  });

  testWidgets('칸을 누르면 알려준다', (tester) async {
    final picked = <ShellTab>[];
    await tester.pumpWidget(host(onSelect: picked.add));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await tester.tap(find.byKey(const ValueKey('nav-me')));
    await tester.pump();

    expect(picked, [ShellTab.gallery, ShellTab.me]);
  });

  testWidgets('고른 칸이 색만이 아니라 모양으로도 구분된다', (tester) async {
    await tester.pumpWidget(host(selected: ShellTab.gallery));
    await tester.pumpAndSettle();

    final slots = tester
        .widgetList<NavSlot>(find.byType(NavSlot))
        .toList();
    expect(slots.where((s) => s.selected), hasLength(1));
    expect(slots.firstWhere((s) => s.selected).tab, ShellTab.gallery);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/bottom_nav_test.dart`
Expected: FAIL — `package:kkumul/shell/bottom_nav.dart` 가 없다.

- [ ] **Step 3: 구현한다**

`app/lib/shell/bottom_nav.dart`:

```dart
import 'package:flutter/material.dart';

/// 셸의 탭 다섯.
///
/// `create` 와 `rank` 는 계획 5·6 의 자리다. 지금 칸을 만들어 두는 것은
/// 상위 스펙 10.1 이 `만들기` 를 중앙의 큰 더하기 버튼으로 분리하라고 해서
/// 그 버튼이 위젯의 구조 자체를 바꾸기 때문이다 — 나중에 끼워 넣으면
/// 64dp 기하를 다시 재야 한다.
enum ShellTab { play, gallery, create, rank, me }

/// 내비 한 줄의 높이. 상위 스펙 10.3 의 최소 터치 타겟이다.
const double kNavHeight = 64;

const _slots = <(ShellTab, IconData, String)>[
  (ShellTab.play, Icons.palette, '놀기'),
  (ShellTab.gallery, Icons.photo_library, '모아보기'),
  (ShellTab.create, Icons.add, '만들기'),
  (ShellTab.rank, Icons.emoji_events, '랭크'),
  (ShellTab.me, Icons.person, '내 정보'),
];

const _green = Color(0xFF246B4B);
const _grey = Color(0xFF6B736C);

/// 고정 하단 내비게이션.
///
/// 색칠 화면에는 올라가지 않는다(설계 스펙 2.1) — 320x640 에서 내비를
/// 넣으면 캔버스가 350 에서 286dp 로 줄어 본문의 절반 아래가 된다.
class BottomNav extends StatelessWidget {
  final ShellTab selected;
  final ValueChanged<ShellTab> onSelect;

  const BottomNav({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      // bottomNavigationBar 는 아래쪽 인셋을 스스로 처리하지 않는다.
      // 감싸지 않으면 64dp 중 아래쪽이 제스처 바 밑으로 들어가 실제 히트
      // 영역이 줄고, 아이가 그 부분을 누르면 탭 대신 홈 제스처가 먹는다.
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kNavHeight,
          child: Row(
            children: [
              // 320dp 에서 Expanded 다섯은 정확히 64dp 씩이다. 더 좁은
              // 화면에서는 넘치는 대신 줄어든다 — 아이에게 칸이 사라지는
              // 것보다 작아지는 편이 낫다.
              for (final (tab, icon, label) in _slots)
                Expanded(
                  child: NavSlot(
                    // 라벨로 찾으면 모호하다 — `내 정보` 는 설정 화면의
                    // 제목이기도 해서, 그 탭에 있을 때 둘이 잡힌다.
                    key: ValueKey('nav-${tab.name}'),
                    tab: tab,
                    icon: icon,
                    label: label,
                    selected: tab == selected,
                    onTap: () => onSelect(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 내비 칸 하나.
///
/// 공개 타입인 것은 테스트가 "다섯 칸이 64dp 를 지키는지"를 직접 재기
/// 위해서다 — 320dp 에 여유가 0 이라 그 테스트가 꼭 필요하다.
class NavSlot extends StatelessWidget {
  final ShellTab tab;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const NavSlot({
    super.key,
    required this.tab,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // `만들기` 는 상위 스펙 10.1 이 "중앙의 큰 더하기 버튼으로 분리"하라고
    // 한 자리다. 색이 아니라 모양으로 구분한다.
    final isCreate = tab == ShellTab.create;
    final tint = selected ? _green : _grey;

    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: kNavHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isCreate)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(icon, size: 22, color: Colors.white),
                  ),
                )
              else
                Icon(icon, size: 26, color: tint),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: isCreate ? _green : tint,
                  // 고른 칸을 색만으로 알리지 않는다.
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 전부 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 224개 (220 + 4).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

세로가 64dp 를 넘쳐 `RenderFlex overflowed` 가 나오면 **라벨 `fontSize` 를 11 보다 줄이지 말고** 아이콘 크기(26)를 먼저 줄인다. 글자가 작아지면 보호자도 못 읽는다.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/shell/bottom_nav.dart app/test/bottom_nav_test.dart
git commit -F - <<'GITEOF'
feat(app): 다섯 칸 하단 내비

놀기 모아보기 만들기 랭크 내 정보. 만들기와 랭크는 계획 5/6 의
자리지만 칸은 지금 만든다 - 중앙 더하기 버튼이 위젯 구조 자체를
바꿔서, 나중에 끼워 넣으면 64dp 기하를 다시 재야 한다.

320dp 에 여유가 0 이라 좁은 화면 테스트를 함께 넣었다. 고른 칸은
색과 굵기 둘로 알린다.
GITEOF
```

---

## Task 11: 셸을 띄운다

탭 다섯을 묶고, 색칠을 띄우고 돌아오면 탭들에게 다시 읽으라고 알린다. 마지막으로 `main()` 을 색칠 화면 직접 띄우기에서 셸 띄우기로 바꾼다.

**Files:**
- Create: `app/lib/shell/shell_screen.dart`
- Create: `app/lib/shell/placeholder_screen.dart`
- Create: `app/test/shell_screen_test.dart`
- Modify: `app/lib/main.dart`

**Interfaces:**
- Consumes: 태스크 5·7·8·9·10 전부
- Produces:
  - `class ShellScreen extends StatefulWidget` — `{required DohanSource source, required ArtworkRepository repository, required SettingsStore settingsStore, required AgeMode initialAgeMode}`
  - `class PlaceholderScreen extends StatelessWidget` — `{required IconData icon, required String title, required String message}`
  - `class KkumulApp extends StatelessWidget` — 같은 인자를 받아 `MaterialApp` 과 `ShellScreen` 을 세운다

### `main.dart` 를 옮길 때 잃기 쉬운 것

지금 `main()` 은 `runApp` **전에** 컨트롤러를 만들어 열고, 그 과정에 두 겹의 복구가 들어 있다.

1. `SettingsStore.load()` 실패를 잡아 기본 연령대로 시작한다 → **`main()` 에 남긴다.**
2. `controller.open()` 실패를 잡아 `-복구-` id 로 다시 연다 → **태스크 5 가 이미 가져갔다.** `main()` 에서는 지운다.

둘 다 지우면 설정 파일 하나가 깨졌을 때 앱이 영영 안 뜬다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/shell_screen_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kkumul/coloring/coloring_route.dart' show ColoringSession;
import 'package:kkumul/core/artwork.dart';
import 'package:kkumul/core/dohan_source.dart';
import 'package:kkumul/gallery/artwork_repository.dart';
import 'package:kkumul/settings/settings.dart';
import 'package:kkumul/shell/bottom_nav.dart';
import 'package:kkumul/shell/placeholder_screen.dart';
import 'package:kkumul/shell/shell_screen.dart';
import 'package:kkumul/ui/art_tile.dart';
import 'package:kkumul/ui/tool_bar.dart';

/// 칠할 수 있는 64x64 도안 하나. 색칠 화면까지 열어 보는 테스트가 쓴다.
class FakeLibrary implements DohanSource {
  static const _ids = ['animal-a', 'car-a', 'dino-a', 'shape-a'];

  @override
  Future<List<String>> listIds() async => _ids;

  @override
  Future<DohanMeta> loadMeta(String id) async => DohanMeta(
        id: id,
        title: '제목 $id',
        category: id.split('-').first == 'dino' ? 'dinosaur' : id.split('-').first,
        source: 'bundled',
        canvasSize: const [64, 64],
        regionCount: 2,
        difficulty: 1,
        suggestedPalette: const [],
        regionAnchors: const {},
        createdAt: DateTime.utc(2026, 10, 6),
      );

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
      meta: await loadMeta(id),
      lineart: img.Image(width: n, height: n, numChannels: 4),
      regions: RegionMap(n, n, ids),
    );
  }
}

void main() {
  late Directory root;
  late ArtworkRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_shell_');
    repository = ArtworkRepository(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Widget host({AgeMode ageMode = AgeMode.toddler}) => MaterialApp(
        home: ShellScreen(
          source: FakeLibrary(),
          repository: repository,
          settingsStore: SettingsStore(root),
          initialAgeMode: ageMode,
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  testWidgets('놀기로 시작하고 탭을 오갈 수 있다', (tester) async {
    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.text('오늘의 그림'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);
    expect(find.byKey(const ValueKey('gallery-empty')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-me')));
    await settle(tester);
    expect(find.byKey(const ValueKey('age-child')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-create')));
    await settle(tester);
    expect(find.byType(PlaceholderScreen), findsOneWidget);
  });

  testWidgets('색칠 화면에는 내비가 없다', (tester) async {
    // 설계 스펙 2.1 — 내비를 넣으면 캔버스가 350 에서 286dp 로 줄어
    // 본문의 절반 아래가 된다.
    await tester.pumpWidget(host());
    await settle(tester);
    expect(find.byType(BottomNav), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('today-tile')));
    await settle(tester);

    expect(find.byKey(const ValueKey('coloring-canvas')), findsOneWidget);
    // 셸의 라우트는 가려져도 트리에 남아 있으므로 전역 findsNothing 은
    // 모호하다. 색칠 화면 **안에** 내비가 없다는 것을 직접 본다.
    expect(
      find.descendant(
        of: find.byType(ColoringSession),
        matching: find.byType(BottomNav),
      ),
      findsNothing,
    );

    await tester.tap(find.text('완성'));
    await settle(tester);

    expect(find.byType(BottomNav), findsOneWidget, reason: '돌아오면 다시 있다');
  });

  testWidgets('놀기에서 그린 그림이 모아보기에 나타난다', (tester) async {
    // 탭이 IndexedStack 안에 살아 있어서 스스로 다시 지어지지 않는다.
    // 셸이 다시 읽으라고 알려 주지 않으면 영영 안 보인다.
    await tester.pumpWidget(host());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('today-tile')));
    await settle(tester);
    final box = tester.getRect(find.byKey(const ValueKey('coloring-canvas')));
    await tester.tapAt(Offset(box.left + box.width * 0.3, box.center.dy));
    await tester.pump();
    await tester.tap(find.text('완성'));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);

    expect(find.byType(ArtTile), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-empty')), findsNothing);
  });

  testWidgets('탭을 오가도 스크롤 위치가 유지된다', (tester) async {
    // 아이가 모아보기를 보다 돌아왔을 때 놀기가 처음으로 튀면 안 된다.
    await tester.pumpWidget(host());
    await settle(tester);

    double playOffset() => Scrollable.of(
          tester.element(find.text('오늘의 그림')),
        ).position.pixels;

    await tester.drag(find.text('오늘의 그림'), const Offset(0, -200));
    await tester.pumpAndSettle();
    final scrolled = playOffset();
    expect(scrolled, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nav-play')));
    await settle(tester);

    expect(playOffset(), scrolled, reason: '처음으로 튀면 안 된다');
  });

  testWidgets('연령대를 바꾸면 다음에 여는 색칠에 적용된다', (tester) async {
    // 계획 3 후속 1.1 의 지뢰가 해체됐는지 본다.
    await tester.pumpWidget(host());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('nav-me')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('age-child')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('nav-play')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('today-tile')));
    await settle(tester);

    expect(find.byType(ToolButton), findsNWidgets(5),
        reason: '새 세션은 새 컨트롤러라 바뀐 설정을 읽는다');
  });

  testWidgets('데이터를 초기화하면 모아보기가 비워진다', (tester) async {
    await repository.save(Artwork(
      id: 'w1',
      dohanId: 'animal-a',
      fills: const {},
      updatedAt: DateTime.utc(2026, 10, 5),
    ));

    await tester.pumpWidget(host());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);
    expect(find.byType(ArtTile), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-me')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('clear-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-confirm')));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('nav-gallery')));
    await settle(tester);

    expect(find.byKey(const ValueKey('gallery-empty')), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd app && C:\src\flutter\bin\flutter test test/shell_screen_test.dart`
Expected: FAIL — `shell_screen.dart` 가 없다.

- [ ] **Step 3: 자리표시자 화면을 만든다**

`app/lib/shell/placeholder_screen.dart`:

```dart
import 'package:flutter/material.dart';

/// 아직 만들지 않은 탭. `만들기`(계획 5)와 `랭크`(계획 6)가 쓴다.
///
/// 출시 전에만 보이는 화면이다. 칸을 지금 만들어 두는 이유는
/// `bottom_nav.dart` 의 [ShellTab] 주석에 있다.
class PlaceholderScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const PlaceholderScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 96, color: const Color(0xFFB7BFB8)),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(color: Color(0xFF6B736C))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 셸을 만든다**

`app/lib/shell/shell_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../coloring/coloring_route.dart';
import '../core/dohan_source.dart';
import '../gallery/artwork_repository.dart';
import '../gallery/gallery_screen.dart';
import '../play/play_screen.dart';
import '../settings/settings.dart';
import '../settings/settings_screen.dart';
import 'bottom_nav.dart';
import 'placeholder_screen.dart';

/// 탭 다섯을 묶는 껍데기.
///
/// 색칠은 탭이 아니라 이 위에 띄운다(설계 스펙 2.1). 그래서 색칠 중에는
/// 내비가 보이지 않고, "다른 탭을 누르면 확인한다"는 요구가 함께 사라진다 —
/// 누를 탭이 없다.
class ShellScreen extends StatefulWidget {
  final DohanSource source;
  final ArtworkRepository repository;
  final SettingsStore settingsStore;
  final AgeMode initialAgeMode;

  const ShellScreen({
    super.key,
    required this.source,
    required this.repository,
    required this.settingsStore,
    required this.initialAgeMode,
  });

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  ShellTab _tab = ShellTab.play;
  late AgeMode _ageMode = widget.initialAgeMode;

  /// 탭들에게 "다시 읽어라"를 알리는 숫자.
  ///
  /// 탭은 `IndexedStack` 안에 살아 있어서(스크롤 위치를 지키려는 것이다)
  /// 스스로 다시 지어지지 않는다. 색칠에서 돌아오거나 데이터를 지웠을 때
  /// 이 값을 올려 주지 않으면 놀기에서 그린 그림이 모아보기에 영영
  /// 나타나지 않는다.
  int _refresh = 0;

  Future<void> _openColoring({
    required String dohanId,
    required String artworkId,
  }) async {
    await openColoring(
      context,
      source: widget.source,
      repository: widget.repository,
      ageMode: _ageMode,
      dohanId: dohanId,
      artworkId: artworkId,
    );
    if (mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFCF8),
      // IndexedStack 은 다섯을 모두 살려 둔다. 탭을 오갈 때 스크롤 위치가
      // 유지되는 것이 이것 때문이다 — 아이가 모아보기를 보다 돌아왔을 때
      // 놀기가 처음으로 튀면 안 된다.
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: ShellTab.values.indexOf(_tab),
          children: [
            PlayScreen(
              source: widget.source,
              repository: widget.repository,
              onOpen: _openColoring,
              refreshToken: _refresh,
            ),
            GalleryScreen(
              repository: widget.repository,
              onOpen: _openColoring,
              refreshToken: _refresh,
            ),
            const PlaceholderScreen(
              icon: Icons.add_a_photo_outlined,
              title: '곧 만들 수 있어요',
              message: '그린 그림을 사진으로 찍어 도안으로 만듭니다',
            ),
            const PlaceholderScreen(
              icon: Icons.emoji_events_outlined,
              title: '곧 열려요',
              message: '색칠하고 만든 만큼 모으는 자리입니다',
            ),
            SettingsScreen(
              store: widget.settingsStore,
              repository: widget.repository,
              ageMode: _ageMode,
              onAgeModeChanged: (mode) => setState(() => _ageMode = mode),
              onDataCleared: () => setState(() => _refresh++),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNav(
        selected: _tab,
        onSelect: (tab) => setState(() => _tab = tab),
      ),
    );
  }
}
```

- [ ] **Step 5: `main.dart` 를 바꾼다**

`app/lib/main.dart` 를 통째로 아래로 바꾼다.

```dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/dohan_source.dart';
import 'gallery/artwork_repository.dart';
import 'library/bundled_dohan_source.dart';
import 'settings/settings.dart';
import 'shell/shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final docs = await getApplicationDocumentsDirectory();
  final settingsStore = SettingsStore(docs);

  // SettingsStore.load() 는 ArtworkRepository.load() 와 같은 원칙으로 읽기
  // 자체가 실패하면(권한·잠김·디스크) 던진다. 따로 감싸서, 설정 파일 하나를
  // 못 읽는다고 앱이 영영 안 뜨는 일이 없게 한다 — 그때는 기본값으로
  // 시작한다. 작품을 못 읽는 경우의 복구는 색칠 세션이 맡는다
  // (`coloring_route.dart` 의 -복구- 경로).
  var ageMode = AgeMode.toddler;
  try {
    ageMode = (await settingsStore.load()).ageMode;
  } on Object catch (error) {
    debugPrint('설정을 읽지 못했습니다 — 기본값으로 시작합니다: $error');
  }

  runApp(KkumulApp(
    source: BundledDohanSource(),
    repository: ArtworkRepository(docs),
    settingsStore: settingsStore,
    initialAgeMode: ageMode,
  ));
}

class KkumulApp extends StatelessWidget {
  final DohanSource source;
  final ArtworkRepository repository;
  final SettingsStore settingsStore;
  final AgeMode initialAgeMode;

  const KkumulApp({
    super.key,
    required this.source,
    required this.repository,
    required this.settingsStore,
    required this.initialAgeMode,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '꼬물꼬물',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246B4B)),
        useMaterial3: true,
      ),
      home: ShellScreen(
        source: source,
        repository: repository,
        settingsStore: settingsStore,
        initialAgeMode: initialAgeMode,
      ),
    );
  }
}
```

- [ ] **Step 6: 전부 돌린다**

Run: `cd app && C:\src\flutter\bin\flutter test`
Expected: PASS, 230개 (224 + 6).

Run: `cd app && C:\src\flutter\bin\flutter analyze`
Expected: `No issues found!`

Run: `cd packages/dohan_core && C:\src\flutter\bin\dart test` → 70개
Run: `cd tools/dohan_cli && C:\src\flutter\bin\dart test` → 14개
Run: `cd tools/dohan_gen && C:\src\flutter\bin\dart test` → 5개

- [ ] **Step 7: 커밋**

```bash
git add app/lib/shell app/lib/main.dart app/test/shell_screen_test.dart
git commit -F - <<'GITEOF'
feat(app): 셸을 띄운다

탭 다섯을 IndexedStack 으로 묶어 스크롤 위치를 지키고, 색칠은
그 위에 띄운다. 색칠 중에는 내비가 보이지 않는다 - 넣으면
캔버스가 350 에서 286dp 로 줄어 본문의 절반 아래가 된다.

탭이 살아 있어서 스스로 다시 지어지지 않으므로, 색칠에서
돌아오거나 데이터를 지웠을 때 셸이 refreshToken 을 올려 다시
읽으라고 알린다.

main() 은 설정 읽기 실패 복구만 남기고 셸을 띄운다. 작품 읽기
실패의 -복구- 경로는 색칠 세션이 가져갔다.
GITEOF
```

---
## 마무리: 전체 확인

모든 태스크가 끝난 뒤 한 번 한다.

- [ ] **Step 1: 네 묶음 모두 초록인지 본다**

```
cd app              && C:\src\flutter\bin\flutter test      # 230개
cd packages/dohan_core && C:\src\flutter\bin\dart test      # 70개
cd tools/dohan_cli  && C:\src\flutter\bin\dart test         # 14개
cd tools/dohan_gen  && C:\src\flutter\bin\dart test         # 5개
cd app              && C:\src\flutter\bin\flutter analyze   # No issues found!
```

- [ ] **Step 2: 작업 트리가 깨끗한지 본다**

Run: `git status --short`
Expected: 아무것도 없다. 중간 산출물(`.lineart-tmp` · `build-dohans.sh`)이 남아 있으면 지운다.

- [ ] **Step 3: 손으로 한 번 돌려 본다 (가능하면)**

Run: `cd app && C:\src\flutter\bin\flutter run -d windows`

Windows 개발자 모드가 꺼져 있으면 빌드가 실패한다. 그때는 **이 단계를 건너뛰고 그 사실을 보고한다** — 개발자 모드를 켜는 것은 사용자의 결정이다.

돌아가면 다음을 눈으로 본다. 테스트가 전부 통과해도 화면에 아무것도 안 나타나는 일이 계획 3 에서 실제로 있었다.

1. 놀기에 도안 열두 장이 **그림으로** 보인다 (회색 네모가 아니다)
2. 도안 하나를 눌러 칠하고 `완성` 을 누른다
3. 모아보기에 그 그림이 **칠한 색 그대로** 보인다
4. 탭을 오가도 놀기의 스크롤 위치가 그대로다
5. 내 정보에서 아동으로 바꾸고 색칠을 열면 도구 줄이 나온다

---

## 이 계획이 끝나면 남는 것

다음 계획이 집어야 할 것들이다. 후속 문서로 옮겨 적는다.

- **가로 모드.** 상위 스펙 10.1 이 요구하지만(우측 세로바) 이 계획은 세로 예산만 맞췄다.
- **즐겨찾기 · 모아보기의 `내 도안`.** 상위 스펙 10.2 의 필수 요소인데 각각 상세가 없고(즐겨찾기) 만드는 화면이 없다(내 도안, 계획 5).
- **효과음과 음소거.** 상위 스펙 10.3 이 요구하지만 **어느 계획에도 배정되지 않았다.** 둘은 같은 계획에서 함께 와야 한다.
- **`lineart@2x.png` 를 아무도 읽지 않는다.** `buildDohan` 이 의도적으로 쓰는데 `BundledDohanSource` 가 경로를 직접 지정해 `rootBundle.load` 하므로 Flutter 의 배율 변형 해석이 걸리지 않는다. 번들에 12장 × 약 48KB ≈ 580KB 가 쓰이지 않고 실려 있다.
- **임계값 보정은 합성 입력으로만 했다.** 설계 스펙 9.1 의 표는 종이 질감도 그림자도 없는 입력에서 나온 것이다. 계획 5 가 실제 사진으로 다시 재야 한다.
- **도안 12장은 자리표시자다.** CC0 선화나 사용자 제공 선화를 같은 경로에 넣으면 코드 변경 없이 바뀐다. 상업적 이용 조건은 `dohan_gen` 의 README 에 적힌 경고 그대로 **먼저 확인해야 한다.**

---

## 실행 방식

**Plan complete and saved to `docs/superpowers/plans/2026-10-06-shell-and-gallery.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — 태스크마다 새 subagent 를 띄우고, 사이사이 리뷰하고, 빠르게 돌린다

**2. Inline Execution** — 이 세션에서 executing-plans 로 묶음 실행하고 체크포인트마다 확인한다

**어느 쪽으로 할까요?**
