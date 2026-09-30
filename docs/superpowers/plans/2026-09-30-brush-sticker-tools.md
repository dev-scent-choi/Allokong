# 브러시 · 스티커 도구 구현 계획 (계획 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 크레용 · 붓 · 지우개 · 스티커 도구와 연령 분기를 붙여, 아이가 영역을 칠하는 것 말고도 자유롭게 그리고 꾸밀 수 있게 한다.

**Architecture:** 브러시 레이어는 오프스크린 이미지에 누적하지 않고 **매 프레임 스트로크 목록을 재생**한다. 되돌리기 리플레이가 공짜로 따라오고 `ui.Image` 회전이 생기지 않는다. 칠할 수 없는 픽셀(선·배경)은 **도안별 정적 마스크 + `BlendMode.dstIn`** 으로 잘라낸다. 되돌리기는 `FillState`·`BrushState`·`StickerState` 를 묶은 `ArtworkState` 하나를 받는 **단일 스택**이라, 아이가 조작한 순서 그대로 되돌아간다.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, `dart:ui` (`Canvas`·`saveLayer`·`BlendMode`), `package:image` (에셋 생성 스크립트), `dohan_core`(계획 1).

**Spec:** `docs/superpowers/specs/2026-09-30-brush-sticker-tools-design.md`
(상위 스펙: `docs/superpowers/specs/2026-09-21-kkumul-coloring-app-design.md` 7·9·10·11장)

**함께 읽을 것:** `docs/superpowers/plans/2026-09-25-coloring-engine-followups.md`

---

## 계획서를 쓰기 전에 실측한 것

계획 1 에서 계획서가 제공한 코드의 버그가 리뷰에 열일곱 번 잡혔다. 구현자의 전사는 매번
정확했다. 그래서 계획 2 부터 **가정을 먼저 실행해 재고** 쓴다. 아래는 이 계획을 쓰기 전에
Flutter 3.47.5 에서 실제로 측정한 값이다.

| 가정 | 실측 결과 |
|---|---|
| `saveLayer` + `dstIn` 마스킹이 칠할 수 없는 픽셀을 잘라내는가 | **그렇다.** 칠할 수 있는 쪽 `[255,0,0,255]`, 선 쪽 `[0,0,0,0]` |
| 1024² 마스크 생성 비용 | **7ms** (도안당 1회) |
| 획 50개 × 점 100개 기록 비용 | **2ms** — 프레임 예산 16.7ms 안 |
| 같은 것을 1024² 이미지로 래스터화 | **14ms** |
| 그 이미지를 PNG 로 인코딩 | **39ms**, 88KB |
| 24색 명도표 | 스펙 7.3.1 의 표가 실측값이다 |

**`brush.png` 한 번 저장 = 14 + 39 = 53ms.** 디바운스마다 이걸 하면 눈에 보이는 끊김이
된다. 그래서 태스크 10 의 "바뀌었을 때만 굽는다"는 최적화가 아니라 **필수**다.

---

## Global Constraints

- 영역 ID `0` = 선 픽셀, `1` = `BACKGROUND`, `2` 이상 = 칠할 수 있는 영역
- 인덱스맵 인코딩: R = ID 하위 8bit, G = ID 상위 8bit, B = 0, A = 255
- 인덱스맵 해상도: 1024 × 1024 고정
- 인덱스맵은 반드시 nearest-neighbor 로만 샘플링한다
- 팔레트 LUT: 256 × 256 RGBA. 영역 ID `n` 은 좌표 `(n % 256, n ~/ 256)`. 알파 0 = 미채색
- 레이어 합성 순서 (아래→위): 흰 배경 → 채움 → 브러시 → 선화 → 스티커
- 터치 타겟 최소 64dp — **UI 버튼에 적용한다.** 도안 영역에는 적용하지 않는다
- 사용자 대면 문자열은 한국어
- 네트워크를 쓰지 않는다
- 브러시는 선(`id == 0`)과 배경(`id == 1`) 위에 남지 않는다. **영역 경계는 넘나든다**
- 스티커 `rotation` 은 포맷에만 두고 항상 `0` 을 쓴다

---

## 환경

Flutter 는 `C:\src\flutter` 에 있고 **PATH 에 없다.** 모든 셸 명령 앞에 붙일 것:

```bash
export PATH="/c/src/flutter/bin:$PATH"
```

- 테스트는 `app/` 에서 `flutter test`
- **`flutter test` 를 `grep` 에 파이프하지 말 것** — 블록 버퍼링 때문에 멈춘 것과 끝난 것이
  구분되지 않는다. 원시 출력을 파일로 받고 `timeout 240` 을 쓸 것
- Bash heredoc 은 이 셸에서 불안정하다. 파일 내용은 Write/Edit 도구로 쓸 것
- `printf` 로 커밋 메시지를 만들지 말 것 — `%` 가 포맷 지시자로 먹힌다. `git commit -F -` 를 쓸 것
- `packages/dohan_core` 와 `tools/` 는 건드리지 않는다 (계획 1, 완료됨)

**시작 상태**: 앱 63 테스트 통과, `flutter analyze` → `No issues found!`. 둘 다 끝까지 유지한다.

**위젯 테스트의 확인된 제약**: `fake_async` 아래에서 이미지 디코딩이 끝나지 않는다. 그래서
위젯 테스트는 저장·타이머를 가짜로 주입하고, 화면은 텍스처가 오기 전에도 캔버스를 올린다.
이것을 "고치려" 들지 말 것.

---

## 파일 구조

**새로 만드는 것**

| 파일 | 책임 |
|---|---|
| `app/lib/ui/palette_shades.dart` | `Shade` 열거형과 확정된 24색 표 |
| `app/lib/coloring/brush_state.dart` | `Stroke` · `BrushState` · 거리 기반 덮임 판정 |
| `app/lib/coloring/sticker_state.dart` | `Sticker` · `StickerState` · 히트 테스트 |
| `app/lib/core/artwork_state.dart` | `ArtworkState` 묶음 |
| `app/lib/coloring/paintable_mask.dart` | `RegionMap` → 마스크 `ui.Image` |
| `app/lib/coloring/brush_painter.dart` | 스트로크 재생 + dstIn 마스크 |
| `app/lib/settings/settings.dart` | `AgeMode` · `settings.json` |
| `app/lib/ui/tool_bar.dart` | 도구 다섯 개 |
| `app/lib/ui/shade_button.dart` | 명도 순환 버튼 |
| `app/lib/ui/sticker_drawer.dart` | 스티커 서랍 |
| `app/tools/make_stickers.dart` | 스티커 PNG 10장 생성 스크립트 |

**고치는 것**

| 파일 | 무엇을 |
|---|---|
| `app/lib/ui/palette_bar.dart` | 명도 단계에 따라 8색 갈아끼우기 |
| `app/lib/core/command.dart` | `apply(FillState)` → `apply(ArtworkState)`, 명령 네 가지 |
| `app/lib/gallery/artwork_repository.dart` | 세 파일 읽기/쓰기 |
| `app/lib/gallery/autosave.dart` | 굽는 함수를 받아 한 번만 부르기 |
| `app/lib/coloring/coloring_controller.dart` | 도구·지우개·배치·유아 제한 |
| `app/lib/ui/coloring_screen.dart` | 레이어 합성, 도구 줄, 상황별 영역, 명도 버튼 |

---

### Task 1: 명도 표와 `Shade`

**Files:**
- Create: `app/lib/ui/palette_shades.dart`
- Test: `app/test/palette_shades_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces: `enum Shade { light, base, dark }` (getter `Shade get next`),
  `const Map<Shade, List<Color>> paletteShades` (각 8색, 순서 고정: 분홍·노랑·주황·파랑·초록·보라·갈색·흰색)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/palette_shades_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/ui/palette_shades.dart';

/// 스펙 7.3 의 공식. 표가 이 공식에서 나왔다는 것을 잠근다.
Color lighter(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness(h.lightness + (1 - h.lightness) * 0.45).toColor();
}

Color darker(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness * 0.62).clamp(0.0, 1.0)).toColor();
}

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('세 단계 모두 여덟 색이다', () {
    for (final shade in Shade.values) {
      expect(paletteShades[shade], hasLength(8), reason: '$shade');
    }
  });

  test('기본 단계는 상위 스펙 9장의 값 그대로다', () {
    expect(paletteShades[Shade.base], const [
      Color(0xFFEF7586),
      Color(0xFFF1BD45),
      Color(0xFFEF8A45),
      Color(0xFF6CAEE0),
      Color(0xFF63B98B),
      Color(0xFF9E82CF),
      Color(0xFF795548),
      Color(0xFFF5F5F5),
    ]);
  });

  test('밝은 단계가 공식과 일치한다', () {
    final base = paletteShades[Shade.base]!;
    final light = paletteShades[Shade.light]!;
    for (var i = 0; i < 8; i++) {
      expect(light[i], lighter(base[i]),
          reason: '$i 번째 색이 공식과 어긋난다 — 표를 고치거나 공식을 고쳐야 한다');
    }
  });

  test('어두운 단계가 공식과 일치한다', () {
    final base = paletteShades[Shade.base]!;
    final dark = paletteShades[Shade.dark]!;
    for (var i = 0; i < 8; i++) {
      expect(dark[i], darker(base[i]), reason: '$i 번째 색이 공식과 어긋난다');
    }
  });

  test('명도를 누르면 밝게 → 기본 → 어둡게 로 돌고 되돌아온다', () {
    expect(Shade.light.next, Shade.base);
    expect(Shade.base.next, Shade.dark);
    expect(Shade.dark.next, Shade.light);
  });

  test('테두리색이 24색 전부에서 배경과 구분된다', () {
    // 계획 2 가 잡은 "흰 크레용이 안 보인다"(1.06:1)의 재발을 막는다.
    // 스와치 안쪽 색이 배경에 묻혀도 테두리는 항상 보여야 한다.
    const page = Color(0xFFFCFCF8);
    const border = Color(0xFF757D75);
    expect(contrast(border, page), greaterThanOrEqualTo(3.0));
  });

  test('같은 단계 안에서 여덟 색이 서로 다르다', () {
    for (final shade in Shade.values) {
      final seen = paletteShades[shade]!.map((c) => c.toARGB32()).toSet();
      expect(seen, hasLength(8), reason: '$shade 에 중복된 색이 있다');
    }
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/palette_shades_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/ui/palette_shades.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/ui/palette_shades.dart`:

```dart
import 'package:flutter/painting.dart' show Color;

/// 팔레트 명도 단계.
///
/// 상위 스펙 9장은 아동 팔레트를 24색(8색 × 3명도)이라고 하지만, 64dp 스와치
/// 24개는 320dp 화면에서 본문의 59% 를 먹는다. 그래서 스와치는 8개로 두고
/// 명도를 별개 축으로 뺐다 — 설계 문서 3.2절.
enum Shade {
  light,
  base,
  dark;

  /// 앱바의 명도 버튼이 한 바퀴 돈다.
  Shade get next => Shade.values[(index + 1) % Shade.values.length];
}

/// 명도별 8색. 순서는 분홍 · 노랑 · 주황 · 파랑 · 초록 · 보라 · 갈색 · 흰색.
///
/// **상수 표로 고정한다.** 런타임에 HSL 변환을 돌리면 기기마다 반올림이 달라질
/// 수 있다. 이 값들이 스펙 7.3 의 공식에서 나왔다는 것은
/// `palette_shades_test.dart` 가 공식과 대조해 잠근다 — 표가 계약이고 공식은
/// 표가 어떻게 나왔는지를 설명하는 근거다.
///
/// 흰색의 `light`(`#fafafa`)가 `base`(`#f5f5f5`)와 거의 같아 보이는 것은 결함이
/// 아니라 흰색의 성질이다. 더 밝아질 자리가 없다.
const Map<Shade, List<Color>> paletteShades = {
  Shade.light: [
    Color(0xFFF6B3BC),
    Color(0xFFF7DB99),
    Color(0xFFF6BF99),
    Color(0xFFAED2EE),
    Color(0xFFA9D9BF),
    Color(0xFFCABAE5),
    Color(0xFFBE9D92),
    Color(0xFFFAFAFA),
  ],
  Shade.base: [
    Color(0xFFEF7586),
    Color(0xFFF1BD45),
    Color(0xFFEF8A45),
    Color(0xFF6CAEE0),
    Color(0xFF63B98B),
    Color(0xFF9E82CF),
    Color(0xFF795548),
    Color(0xFFF5F5F5),
  ],
  Shade.dark: [
    Color(0xFFC6172F),
    Color(0xFFB3810D),
    Color(0xFFB0500F),
    Color(0xFF2470AA),
    Color(0xFF377A56),
    Color(0xFF5C3A97),
    Color(0xFF4B352D),
    Color(0xFF989898),
  ],
};
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/palette_shades_test.dart
```

Expected: PASS — 7개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -F - <<'MSG'
feat(app): 팔레트 명도 단계와 확정된 24색 표
MSG
```

---

### Task 2: `PaletteBar` 명도 지원과 좁은 화면 검증

**Files:**
- Modify: `app/lib/ui/palette_bar.dart`
- Test: `app/test/palette_bar_test.dart`

**Interfaces:**
- Consumes: `Shade`, `paletteShades` (Task 1)
- Produces: `PaletteBar({required Shade shade, required int selectedIndex, required ValueChanged<int> onPickIndex})` — 색이 아니라 **인덱스**를 주고받는다. 명도가 바뀌어도 아이가 고른 색의 자리는 그대로여야 한다.

`ColorSwatchButton` 은 계획 2 의 것을 그대로 둔다(64dp, `#757D75` 테두리).

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/palette_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/ui/palette_bar.dart';
import 'package:kkumul/ui/palette_shades.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Column(children: [const Spacer(), child])),
    );

void main() {
  testWidgets('고른 명도의 여덟 색을 보여준다', (tester) async {
    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.dark,
      selectedIndex: 0,
      onPickIndex: (_) {},
    )));

    final swatches = find.byType(ColorSwatchButton);
    expect(swatches, findsNWidgets(8));

    final first = tester.widget<ColorSwatchButton>(swatches.first);
    expect(first.color, paletteShades[Shade.dark]!.first);
  });

  testWidgets('색을 누르면 인덱스를 준다', (tester) async {
    int? picked;
    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.base,
      selectedIndex: 0,
      onPickIndex: (i) => picked = i,
    )));

    await tester.tap(find.byType(ColorSwatchButton).at(4));
    expect(picked, 4,
        reason: '색이 아니라 자리를 준다 — 명도가 바뀌어도 자리는 유지된다');
  });

  testWidgets('좁은 화면에서도 여덟 색이 전부 화면 안에 있고 64dp 를 지킨다',
      (tester) async {
    // 계획 2 는 위젯 테스트가 전부 800x600 에서 돌아, 여덟 색 중 둘이 화면
    // 밖으로 밀린 것을 태스크 리뷰 열 번이 놓쳤다. 이번에는 1번 태스크부터 본다.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.base,
      selectedIndex: 3,
      onPickIndex: (_) {},
    )));

    final swatches = find.byType(ColorSwatchButton);
    expect(swatches, findsNWidgets(8));

    for (final e in swatches.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320),
          reason: '화면 밖으로 밀려난 색은 아이에게 없는 색이다');
    }
  });

  testWidgets('고른 자리만 선택 표시가 켜진다', (tester) async {
    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.base,
      selectedIndex: 6,
      onPickIndex: (_) {},
    )));

    final swatches = find.byType(ColorSwatchButton);
    for (var i = 0; i < 8; i++) {
      expect(tester.widget<ColorSwatchButton>(swatches.at(i)).selected, i == 6,
          reason: '$i 번째');
    }
  });

  testWidgets('명도를 바꿔도 고른 자리는 그대로다', (tester) async {
    await tester.pumpWidget(_host(PaletteBar(
      shade: Shade.light,
      selectedIndex: 6,
      onPickIndex: (_) {},
    )));

    final swatches = find.byType(ColorSwatchButton);
    expect(tester.widget<ColorSwatchButton>(swatches.at(6)).selected, isTrue);
    expect(tester.widget<ColorSwatchButton>(swatches.at(6)).color,
        paletteShades[Shade.light]![6]);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/palette_bar_test.dart
```

Expected: FAIL — `PaletteBar` 의 생성자가 `colors`/`selected`/`onPick` 을 요구하므로
`No named parameter with the name 'shade'` 로 컴파일이 깨진다.

- [ ] **Step 3: `PaletteBar` 수정**

`app/lib/ui/palette_bar.dart` 에서 `PaletteBar` 클래스 전체를 아래로 바꾼다.
`ColorSwatchButton` 은 **건드리지 않는다.** 파일 상단 import 에 아래를 추가한다:

```dart
import 'palette_shades.dart';
```

그리고 `PaletteBar` 를:

```dart
/// 색 고르는 줄.
///
/// 색이 아니라 **자리(index)** 를 주고받는다. 명도 버튼을 누르면 여덟 색이
/// 통째로 바뀌는데, 그때도 아이가 고른 자리는 그대로여야 하기 때문이다.
class PaletteBar extends StatelessWidget {
  final Shade shade;
  final int selectedIndex;
  final ValueChanged<int> onPickIndex;

  const PaletteBar({
    super.key,
    required this.shade,
    required this.selectedIndex,
    required this.onPickIndex,
  });

  @override
  Widget build(BuildContext context) {
    final colors = paletteShades[shade]!;
    // Wrap 이지 가로 ListView 가 아니다. 64dp 여덟 개는 512dp 라 좁은 기기에서
    // 마지막 두 색이 화면 밖으로 밀려나고, 글을 못 읽는 아이는 줄이 옆으로
    // 스크롤된다는 것을 알아낼 방법이 없다 — 보이지 않는 색은 없는 색이다.
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < colors.length; i++)
          ColorSwatchButton(
            color: colors[i],
            selected: i == selectedIndex,
            onTap: () => onPickIndex(i),
          ),
      ],
    );
  }
}
```

기존 `PaletteBar.toddlerPalette` 상수는 지운다 — `paletteShades[Shade.base]` 가 같은 값이다.

- [ ] **Step 4: 테스트 실패 확인 (호출부)**

```bash
cd app && flutter analyze
```

Expected: `coloring_screen.dart` 가 `PaletteBar.toddlerPalette` 와 옛 생성자를 쓰므로 에러가 난다.
**이것은 예상된 것이다.** 태스크 13 이 화면을 고칠 때까지 임시로 맞춰 둔다:
`coloring_screen.dart` 의 `PaletteBar(...)` 호출을 아래로 바꾼다.

```dart
            child: PaletteBar(
              shade: Shade.base,
              selectedIndex: _paletteIndex,
              onPickIndex: (i) {
                setState(() => _paletteIndex = i);
                c.pickColor(paletteShades[Shade.base]![i]);
              },
            ),
```

`_ColoringScreenState` 에 `int _paletteIndex = 0;` 을 추가하고,
`import 'palette_shades.dart';` 를 추가한다.

- [ ] **Step 5: 전체 테스트와 분석 확인**

```bash
cd app && flutter test
cd app && flutter analyze
```

Expected: 전부 통과, `No issues found!`
(계획 2 의 `coloring_screen_test.dart` 가 `ColorSwatchButton` 을 개수로만 보므로 계속 통과한다.)

- [ ] **Step 6: 커밋**

```bash
git add app
git commit -F - <<'MSG'
feat(app): 팔레트가 명도 단계를 받고 자리로 색을 고른다
MSG
```

---

### Task 3: `Stroke` 와 `BrushState`

**Files:**
- Create: `app/lib/coloring/brush_state.dart`
- Test: `app/test/brush_state_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum BrushKind { crayon, brush, eraser }`
  - `class Stroke { BrushKind kind; Color color; double width; List<Offset> points; bool covers(Offset) }`
  - `class BrushState { ui.Image? base; List<Stroke> strokes; Stroke? live; bool get isEmpty; bool hasInkAt(Offset); int revision; void clear() }`
  - `const double kCrayonWidth = 24, kBrushWidth = 48, kEraserWidth = 48;`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/brush_state_test.dart`:

```dart
import 'dart:ui' show Offset;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/brush_state.dart';

Stroke _line(List<Offset> pts, {BrushKind kind = BrushKind.crayon}) => Stroke(
      kind: kind,
      color: const Color(0xFFEF7586),
      width: 24,
      points: pts,
    );

void main() {
  test('획 위의 점은 덮여 있다', () {
    final s = _line(const [Offset(0, 0), Offset(100, 0)]);
    expect(s.covers(const Offset(50, 0)), isTrue);
    expect(s.covers(const Offset(50, 11)), isTrue, reason: '굵기 24 의 절반 안');
  });

  test('획에서 굵기 절반보다 먼 점은 덮여 있지 않다', () {
    final s = _line(const [Offset(0, 0), Offset(100, 0)]);
    expect(s.covers(const Offset(50, 13)), isFalse);
    expect(s.covers(const Offset(200, 0)), isFalse, reason: '선분 밖으로 연장되지 않는다');
  });

  test('점이 하나인 획은 원으로 친다', () {
    final s = _line(const [Offset(10, 10)]);
    expect(s.covers(const Offset(10, 21)), isTrue);
    expect(s.covers(const Offset(10, 23)), isFalse);
  });

  test('꺾인 획은 각 선분에서 판정한다', () {
    final s = _line(const [Offset(0, 0), Offset(100, 0), Offset(100, 100)]);
    expect(s.covers(const Offset(100, 50)), isTrue, reason: '두 번째 선분 위');
    expect(s.covers(const Offset(50, 50)), isFalse, reason: '두 선분 사이의 빈 곳');
  });

  test('지우개 획은 잉크로 치지 않는다', () {
    final b = BrushState()
      ..strokes.add(_line(const [Offset(0, 0), Offset(100, 0)],
          kind: BrushKind.eraser));
    expect(b.hasInkAt(const Offset(50, 0)), isFalse,
        reason: '지우개는 잉크를 없앤 자국이지 잉크가 아니다');
  });

  test('크레용 획은 잉크로 친다', () {
    final b = BrushState()
      ..strokes.add(_line(const [Offset(0, 0), Offset(100, 0)]));
    expect(b.hasInkAt(const Offset(50, 0)), isTrue);
    expect(b.hasInkAt(const Offset(50, 90)), isFalse);
  });

  test('빈 상태를 알아본다', () {
    final b = BrushState();
    expect(b.isEmpty, isTrue);
    b.strokes.add(_line(const [Offset(0, 0)]));
    expect(b.isEmpty, isFalse);
  });

  test('획이 늘거나 줄면 개정 번호가 바뀐다', () {
    // 자동 저장이 "브러시가 바뀌었는가"를 이걸로 판단한다. 바뀌지 않았으면
    // 1024 PNG 를 굽지 않는다 (53ms).
    final b = BrushState();
    final r0 = b.revision;
    b.push(_line(const [Offset(0, 0), Offset(10, 10)]));
    expect(b.revision, isNot(r0));
    final r1 = b.revision;
    b.removeStroke(b.strokes.last);
    expect(b.revision, isNot(r1));
  });

  test('clear 는 획과 바탕을 모두 비운다', () {
    final b = BrushState()..strokes.add(_line(const [Offset(0, 0)]));
    b.clear();
    expect(b.isEmpty, isTrue);
    expect(b.strokes, isEmpty);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/brush_state_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/coloring/brush_state.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/coloring/brush_state.dart`:

```dart
import 'dart:ui' as ui;
import 'dart:ui' show Offset;

import 'package:flutter/painting.dart' show Color;

/// 스펙 7.4 의 굵기. 캔버스(1024) 좌표 기준이다.
const double kCrayonWidth = 24;
const double kBrushWidth = 48;
const double kEraserWidth = 48;

enum BrushKind { crayon, brush, eraser }

/// 한 번의 획.
class Stroke {
  final BrushKind kind;

  /// `eraser` 일 때는 쓰이지 않는다 — 지우개는 색이 아니라 `BlendMode.clear` 다.
  final Color color;

  final double width;
  final List<Offset> points;

  const Stroke({
    required this.kind,
    required this.color,
    required this.width,
    required this.points,
  });

  /// [p] 가 이 획에 덮여 있는가.
  ///
  /// 픽셀을 읽지 않는다. 브러시 레이어는 우리가 직접 재생하므로 기하로 정확히
  /// 알 수 있고, 획 50개 × 점 100개라도 판정 한 번에 5천 번 거리 계산이라
  /// 탭 한 번에는 문제가 되지 않는다.
  bool covers(Offset p) {
    if (points.isEmpty) return false;
    final r = width / 2;
    if (points.length == 1) return (points.first - p).distance <= r;
    for (var i = 0; i < points.length - 1; i++) {
      if (_distanceToSegment(p, points[i], points[i + 1]) <= r) return true;
    }
    return false;
  }
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final abx = b.dx - a.dx;
  final aby = b.dy - a.dy;
  final len2 = abx * abx + aby * aby;
  if (len2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2).clamp(0.0, 1.0);
  return (p - Offset(a.dx + abx * t, a.dy + aby * t)).distance;
}

/// 브러시 레이어 상태.
///
/// 획을 오프스크린 이미지에 누적하지 않는다. `ui.Image` 는 불변이라 덧그리려면
/// 매번 새 이미지를 만들어야 하고, 1024² 면 한 장에 4MB 다. 대신 매 프레임
/// 목록을 재생한다 — 실측 2ms — 그러면 되돌리기 리플레이도 공짜로 따라온다.
class BrushState {
  /// 이전 세션에서 구운 `brush.png`. 없으면 null.
  ui.Image? base;

  /// 이번 세션에 그은 획들.
  final List<Stroke> strokes = [];

  /// 지금 손가락이 그리고 있는 중인 획. 아직 명령으로 쌓이지 않았다.
  Stroke? live;

  int _revision = 0;

  /// 마지막 저장 이후 브러시가 바뀌었는지 판단하는 값.
  int get revision => _revision;

  bool get isEmpty => base == null && strokes.isEmpty && live == null;

  void push(Stroke s) {
    strokes.add(s);
    _revision++;
  }

  void removeStroke(Stroke s) {
    strokes.remove(s);
    _revision++;
  }

  /// [p] 를 이번 세션의 **잉크** 획이 덮고 있는가.
  ///
  /// 지우개 획은 제외한다 — 잉크를 없앤 자국이지 잉크가 아니다. 나중 지우개가
  /// 앞선 잉크를 지웠는지까지 순서대로 되짚지는 않는다. 이 판정의 용도(채움을
  /// 벗길지 말지)에 그 정밀도는 필요 없다.
  bool hasInkAt(Offset p) {
    for (final s in strokes) {
      if (s.kind != BrushKind.eraser && s.covers(p)) return true;
    }
    return false;
  }

  void clear() {
    strokes.clear();
    live = null;
    base = null;
    _revision++;
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/brush_state_test.dart
```

Expected: PASS — 10개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -F - <<'MSG'
feat(app): 브러시 획 상태와 거리 기반 덮임 판정
MSG
```

---

### Task 4: `Sticker` 와 `StickerState`

**Files:**
- Create: `app/lib/coloring/sticker_state.dart`
- Test: `app/test/sticker_state_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `class Sticker { String instanceId, stickerId; double x, y, scale, rotation; Rect get bounds; bool contains(Offset); Sticker copyWith(...); Map<String,dynamic> toJson(); factory Sticker.fromJson(...) }`
  - `static const double Sticker.baseSize = 160, minScale = 0.5, maxScale = 2.0`
  - `class StickerState { List<Sticker> stickers; Sticker? topAt(Offset); int indexOf(String); void insertAt(int, Sticker); void removeAt(int); void replaceAt(int, Sticker); void clear(); List<Map<String,dynamic>> toJson(); void loadJson(List) }`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/sticker_state_test.dart`:

```dart
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/sticker_state.dart';

Sticker _at(String id, double x, double y, {double scale = 1.0}) =>
    Sticker(instanceId: id, stickerId: 'star-01', x: x, y: y, scale: scale);

void main() {
  test('기본 크기는 160px 이고 배율이 곱해진다', () {
    expect(_at('a', 0, 0).bounds.width, 160);
    expect(_at('a', 0, 0, scale: 2.0).bounds.width, 320);
  });

  test('경계 안의 점을 알아본다', () {
    final s = _at('a', 500, 500);
    expect(s.contains(const Offset(500, 500)), isTrue);
    expect(s.contains(const Offset(570, 500)), isTrue, reason: '반폭 80 안');
    expect(s.contains(const Offset(590, 500)), isFalse);
  });

  test('겹치면 나중에 붙인 것이 위다', () {
    final st = StickerState()
      ..insertAt(0, _at('아래', 500, 500))
      ..insertAt(1, _at('위', 510, 500));
    expect(st.topAt(const Offset(505, 500))!.instanceId, '위');
  });

  test('아무것도 없는 곳은 null 이다', () {
    final st = StickerState()..insertAt(0, _at('a', 100, 100));
    expect(st.topAt(const Offset(900, 900)), isNull);
  });

  test('자리를 지정해 넣고 뺄 수 있다', () {
    // 되돌리기가 z 순서까지 정확히 복원하려면 자리가 필요하다.
    final st = StickerState()
      ..insertAt(0, _at('a', 0, 0))
      ..insertAt(1, _at('b', 0, 0))
      ..insertAt(2, _at('c', 0, 0));
    st.removeAt(1);
    expect(st.stickers.map((s) => s.instanceId), ['a', 'c']);
    st.insertAt(1, _at('b', 0, 0));
    expect(st.stickers.map((s) => s.instanceId), ['a', 'b', 'c']);
  });

  test('자리를 지켜 바꿔치기한다', () {
    final st = StickerState()
      ..insertAt(0, _at('a', 0, 0))
      ..insertAt(1, _at('b', 10, 10));
    st.replaceAt(0, _at('a', 99, 99));
    expect(st.stickers.first.x, 99);
    expect(st.stickers.map((s) => s.instanceId), ['a', 'b']);
  });

  test('instanceId 로 자리를 찾는다', () {
    final st = StickerState()
      ..insertAt(0, _at('a', 0, 0))
      ..insertAt(1, _at('b', 0, 0));
    expect(st.indexOf('b'), 1);
    expect(st.indexOf('없음'), -1);
  });

  test('JSON 으로 왕복한다', () {
    final st = StickerState()
      ..insertAt(0, _at('a', 12, 34, scale: 1.5))
      ..insertAt(1, _at('b', 56, 78));

    final back = StickerState()..loadJson(st.toJson());

    expect(back.stickers, hasLength(2));
    expect(back.stickers.first.instanceId, 'a');
    expect(back.stickers.first.x, 12);
    expect(back.stickers.first.scale, 1.5);
    expect(back.stickers.last.instanceId, 'b');
  });

  test('회전은 포맷에만 있고 항상 0 이다', () {
    final s = _at('a', 0, 0);
    expect(s.rotation, 0);
    expect(s.toJson()['rotation'], 0);
  });

  test('배율은 범위 안으로 갇힌다', () {
    expect(_at('a', 0, 0, scale: 9.0).scale, Sticker.maxScale);
    expect(_at('a', 0, 0, scale: 0.01).scale, Sticker.minScale);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/sticker_state_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/coloring/sticker_state.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/coloring/sticker_state.dart`:

```dart
import 'dart:ui' show Offset, Rect;

/// 캔버스에 붙인 스티커 하나.
///
/// 래스터로 굽지 않고 오브젝트로 둔다(상위 스펙 7.4). 개별 이동·삭제가 되고,
/// 되돌리기가 단순하며, 저장 용량이 사실상 0 이다.
class Sticker {
  /// 이 배치 한 건의 id. 같은 그림을 여러 번 붙일 수 있으므로 [stickerId] 와 다르다.
  final String instanceId;

  /// 어떤 스티커 그림인가. 예: `star-01`
  final String stickerId;

  /// 캔버스 좌표. 스티커의 **중심**이다.
  final double x;
  final double y;

  final double scale;

  /// 항상 0. 포맷 호환을 위해 자리만 둔다 — 두 손가락으로 크기와 회전을 동시에
  /// 다루는 것은 6~9세에게 어렵고 대개 의도치 않게 비뚤어진다. 나중에 포맷을
  /// 바꾸지 않고 제스처만 추가할 수 있다.
  final double rotation;

  static const double baseSize = 160;
  static const double minScale = 0.5;
  static const double maxScale = 2.0;

  Sticker({
    required this.instanceId,
    required this.stickerId,
    required this.x,
    required this.y,
    double scale = 1.0,
    this.rotation = 0,
  }) : scale = scale.clamp(minScale, maxScale);

  double get size => baseSize * scale;

  Rect get bounds =>
      Rect.fromCenter(center: Offset(x, y), width: size, height: size);

  bool contains(Offset p) => bounds.contains(p);

  Sticker copyWith({double? x, double? y, double? scale}) => Sticker(
        instanceId: instanceId,
        stickerId: stickerId,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation,
      );

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'stickerId': stickerId,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
      };

  factory Sticker.fromJson(Map<String, dynamic> j) => Sticker(
        instanceId: j['instanceId'] as String,
        stickerId: j['stickerId'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        scale: (j['scale'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
      );
}

/// 붙인 스티커 목록. 뒤에 있는 것이 위에 그려진다.
class StickerState {
  final List<Sticker> stickers = [];

  /// [p] 아래에서 **맨 위** 스티커를 찾는다.
  Sticker? topAt(Offset p) {
    for (var i = stickers.length - 1; i >= 0; i--) {
      if (stickers[i].contains(p)) return stickers[i];
    }
    return null;
  }

  int indexOf(String instanceId) =>
      stickers.indexWhere((s) => s.instanceId == instanceId);

  /// 되돌리기가 z 순서까지 복원해야 하므로 자리를 지정해 넣는다.
  void insertAt(int index, Sticker s) => stickers.insert(index, s);

  void removeAt(int index) => stickers.removeAt(index);

  void replaceAt(int index, Sticker s) => stickers[index] = s;

  void clear() => stickers.clear();

  List<Map<String, dynamic>> toJson() =>
      [for (final s in stickers) s.toJson()];

  void loadJson(List<dynamic> json) {
    stickers.clear();
    for (final e in json) {
      stickers.add(Sticker.fromJson(e as Map<String, dynamic>));
    }
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/sticker_state_test.dart
```

Expected: PASS — 10개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -F - <<'MSG'
feat(app): 스티커 오브젝트와 히트 테스트
MSG
```

---

### Task 5: `ArtworkState` 와 명령 네 가지

**Files:**
- Create: `app/lib/core/artwork_state.dart`
- Modify: `app/lib/core/command.dart` (전면 교체)
- Modify: `app/test/command_test.dart` (기존 5개 테스트를 새 시그니처로 이관 + 새 테스트)
- Modify: `app/lib/coloring/coloring_controller.dart` (호출부만)

**Interfaces:**
- Consumes: `FillState`(계획 2), `BrushState`·`Stroke`(Task 3), `StickerState`·`Sticker`(Task 4)
- Produces:
  - `class ArtworkState { FillState fills; BrushState brush; StickerState stickers; void clear() }`
  - `abstract class Command { void apply(ArtworkState); void revert(ArtworkState) }`
  - `FillCommand({required int regionId, required Color? before, required Color? after})`
  - `StrokeCommand(Stroke stroke)`
  - `StickerCommand({required int index, required Sticker? before, required Sticker? after})`
  - `BatchCommand(List<Command> commands)`
  - `UndoStack({int depth = 50})` — `push(Command, ArtworkState)`, `undo(ArtworkState) → bool`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/command_test.dart` 를 **통째로** 아래로 바꾼다:

```dart
import 'dart:ui' show Offset;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/brush_state.dart';
import 'package:kkumul/coloring/sticker_state.dart';
import 'package:kkumul/core/artwork_state.dart';
import 'package:kkumul/core/command.dart';

const _pink = Color(0xFFEF7586);
const _blue = Color(0xFF6CAEE0);

Stroke _stroke() => const Stroke(
      kind: BrushKind.crayon,
      color: _pink,
      width: 24,
      points: [Offset(0, 0), Offset(10, 10)],
    );

Sticker _sticker(String id) =>
    Sticker(instanceId: id, stickerId: 'star-01', x: 100, y: 100);

void main() {
  test('채움 명령이 색을 바꾸고 되돌린다', () {
    final state = ArtworkState();
    UndoStack().push(
      FillCommand(regionId: 2, before: null, after: _pink),
      state,
    );
    expect(state.fills.fillOf(2), _pink);
  });

  test('되돌리면 이전 색으로 간다', () {
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(FillCommand(regionId: 2, before: null, after: _pink), state);
    stack.push(FillCommand(regionId: 2, before: _pink, after: _blue), state);

    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(2), _pink);
    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(2), isNull);
    expect(stack.undo(state), isFalse);
  });

  test('스택 깊이를 넘으면 오래된 것부터 버린다', () {
    final state = ArtworkState();
    final stack = UndoStack(depth: 3);
    for (var i = 0; i < 5; i++) {
      stack.push(
        FillCommand(regionId: 2 + i, before: null, after: _pink),
        state,
      );
    }
    expect(stack.length, 3);
  });

  test('되돌릴 것이 없으면 false 다', () {
    expect(UndoStack().undo(ArtworkState()), isFalse);
  });

  test('clear 하면 되돌릴 것이 없어진다', () {
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(FillCommand(regionId: 2, before: null, after: _pink), state);
    stack.clear();
    expect(stack.canUndo, isFalse);
  });

  test('획 명령이 획을 넣고 뺀다', () {
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(StrokeCommand(_stroke()), state);
    expect(state.brush.strokes, hasLength(1));

    expect(stack.undo(state), isTrue);
    expect(state.brush.strokes, isEmpty);
  });

  test('스티커 명령이 추가·삭제·이동을 되돌린다', () {
    final state = ArtworkState();
    final stack = UndoStack();

    stack.push(
      StickerCommand(index: 0, before: null, after: _sticker('a')),
      state,
    );
    expect(state.stickers.stickers, hasLength(1));

    final moved = state.stickers.stickers.first.copyWith(x: 500);
    stack.push(
      StickerCommand(
          index: 0, before: state.stickers.stickers.first, after: moved),
      state,
    );
    expect(state.stickers.stickers.first.x, 500);

    expect(stack.undo(state), isTrue);
    expect(state.stickers.stickers.first.x, 100, reason: '이동 되돌리기');
    expect(stack.undo(state), isTrue);
    expect(state.stickers.stickers, isEmpty, reason: '추가 되돌리기');
  });

  test('스티커를 지웠다 되돌리면 원래 자리로 돌아온다', () {
    final state = ArtworkState();
    state.stickers
      ..insertAt(0, _sticker('a'))
      ..insertAt(1, _sticker('b'))
      ..insertAt(2, _sticker('c'));

    final stack = UndoStack();
    stack.push(
      StickerCommand(index: 1, before: _sticker('b'), after: null),
      state,
    );
    expect(state.stickers.stickers.map((s) => s.instanceId), ['a', 'c']);

    expect(stack.undo(state), isTrue);
    expect(state.stickers.stickers.map((s) => s.instanceId), ['a', 'b', 'c'],
        reason: 'z 순서까지 복원해야 한다');
  });

  test('묶음 명령은 한 번에 되돌아간다', () {
    // 지우개 한 손짓이 스티커 하나와 채움 셋을 건드려도 되돌리기는 한 번이다.
    final state = ArtworkState();
    state.fills
      ..setFill(2, _pink)
      ..setFill(3, _pink)
      ..setFill(4, _pink);
    state.stickers.insertAt(0, _sticker('a'));

    final stack = UndoStack();
    stack.push(
      BatchCommand([
        StickerCommand(index: 0, before: _sticker('a'), after: null),
        FillCommand(regionId: 2, before: _pink, after: null),
        FillCommand(regionId: 3, before: _pink, after: null),
        FillCommand(regionId: 4, before: _pink, after: null),
      ]),
      state,
    );

    expect(state.stickers.stickers, isEmpty);
    expect(state.fills.filledCount, 0);

    expect(stack.undo(state), isTrue);

    expect(state.stickers.stickers, hasLength(1));
    expect(state.fills.filledCount, 3, reason: '되돌리기 한 번에 넷이 다 돌아온다');
    expect(stack.canUndo, isFalse);
  });

  test('묶음은 역순으로 되돌린다', () {
    // 같은 영역을 두 번 건드린 묶음은 순서를 거꾸로 풀어야 원래대로 돌아온다.
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(
      BatchCommand([
        FillCommand(regionId: 2, before: null, after: _pink),
        FillCommand(regionId: 2, before: _pink, after: _blue),
      ]),
      state,
    );
    expect(state.fills.fillOf(2), _blue);

    expect(stack.undo(state), isTrue);
    expect(state.fills.fillOf(2), isNull,
        reason: '역순이 아니면 분홍이 남는다');
  });

  test('조작 순서 그대로 거꾸로 되돌아간다', () {
    // 레이어별로 스택을 쪼개면 깨지는 성질이다.
    final state = ArtworkState();
    final stack = UndoStack();
    stack.push(FillCommand(regionId: 2, before: null, after: _pink), state);
    stack.push(StrokeCommand(_stroke()), state);
    stack.push(
      StickerCommand(index: 0, before: null, after: _sticker('a')),
      state,
    );

    stack.undo(state);
    expect(state.stickers.stickers, isEmpty, reason: '스티커가 먼저');
    stack.undo(state);
    expect(state.brush.strokes, isEmpty, reason: '그다음 획');
    stack.undo(state);
    expect(state.fills.filledCount, 0, reason: '마지막이 채움');
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/command_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/core/artwork_state.dart'`

- [ ] **Step 3: `ArtworkState` 작성**

`app/lib/core/artwork_state.dart`:

```dart
import '../coloring/brush_state.dart';
import '../coloring/fill_state.dart';
import '../coloring/sticker_state.dart';

/// 한 작품의 편집 상태 전부.
///
/// 명령이 이것 하나를 받는다. 레이어마다 스택을 따로 두면 아이 경험이 깨진다 —
/// 칠하고 → 긋고 → 스티커를 붙인 뒤 되돌리기를 세 번 누르면 스티커 → 획 → 채움
/// 순으로 돌아가야 하는데, 스택이 갈라지면 그 순서를 지킬 수 없다.
class ArtworkState {
  final FillState fills;
  final BrushState brush;
  final StickerState stickers;

  ArtworkState({
    FillState? fills,
    BrushState? brush,
    StickerState? stickers,
  })  : fills = fills ?? FillState(),
        brush = brush ?? BrushState(),
        stickers = stickers ?? StickerState();

  void clear() {
    fills.clear();
    brush.clear();
    stickers.clear();
  }
}
```

- [ ] **Step 4: `command.dart` 전면 교체**

`app/lib/core/command.dart` 를 통째로 아래로 바꾼다:

```dart
import 'dart:collection';

import 'package:flutter/painting.dart' show Color;

import '../coloring/brush_state.dart';
import '../coloring/sticker_state.dart';
import 'artwork_state.dart';

/// 되돌릴 수 있는 한 번의 조작.
abstract class Command {
  void apply(ArtworkState state);
  void revert(ArtworkState state);
}

/// 영역 하나의 색을 바꾼 일. `after == null` 이 "칠 지우기"다.
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
  void apply(ArtworkState state) => state.fills.setFill(regionId, after);

  @override
  void revert(ArtworkState state) => state.fills.setFill(regionId, before);
}

/// 획 하나를 그은 일.
///
/// 획에는 바꿔칠 정체성이 없으므로 이전/이후가 아니라 획 자체를 들고 있다.
/// 지우개 획도 이것으로 쌓인다 — 지우개는 잉크를 없애는 획이지 획의 삭제가 아니다.
class StrokeCommand implements Command {
  final Stroke stroke;

  const StrokeCommand(this.stroke);

  @override
  void apply(ArtworkState state) => state.brush.push(stroke);

  @override
  void revert(ArtworkState state) => state.brush.removeStroke(stroke);
}

/// 스티커 하나를 붙이거나 떼거나 옮긴 일.
///
/// [index] 는 z 순서다. 떼었다가 되돌릴 때 원래 자리로 돌아가야 한다.
class StickerCommand implements Command {
  final int index;
  final Sticker? before;
  final Sticker? after;

  const StickerCommand({
    required this.index,
    required this.before,
    required this.after,
  });

  @override
  void apply(ArtworkState state) => _set(state, before, after);

  @override
  void revert(ArtworkState state) => _set(state, after, before);

  void _set(ArtworkState state, Sticker? from, Sticker? to) {
    if (from == null && to != null) {
      state.stickers.insertAt(index, to);
    } else if (from != null && to == null) {
      state.stickers.removeAt(index);
    } else if (from != null && to != null) {
      state.stickers.replaceAt(index, to);
    }
  }
}

/// 한 번의 손짓이 만든 명령 여러 개를 하나로 묶는다.
///
/// 지우개가 "손가락 밑의 맨 위 것"을 지우므로, 한 번 쓸어내리는 동안 브러시
/// 자국을 지우는 획 하나와 벗겨진 채움 여러 개가 함께 나온다. 아이는 되돌리기
/// 한 번에 그 손짓 전체가 돌아오기를 기대한다.
class BatchCommand implements Command {
  final List<Command> commands;

  const BatchCommand(this.commands);

  @override
  void apply(ArtworkState state) {
    for (final c in commands) {
      c.apply(state);
    }
  }

  @override
  void revert(ArtworkState state) {
    // 역순이어야 한다. 같은 대상을 두 번 건드린 묶음은 거꾸로 풀지 않으면
    // 중간 상태가 남는다.
    for (final c in commands.reversed) {
      c.revert(state);
    }
  }
}

/// 되돌리기 스택.
///
/// 다시 실행(redo)은 두지 않는다. 이 연령대에서 되돌리기는 "실수를 쉽게 지우는"
/// 장치이지 편집 히스토리가 아니고, redo 버튼이 하나 더 늘면 도구바가 그만큼
/// 복잡해진다.
class UndoStack {
  final int depth;
  final Queue<Command> _stack = Queue<Command>();

  UndoStack({this.depth = 50});

  bool get canUndo => _stack.isNotEmpty;

  int get length => _stack.length;

  void push(Command command, ArtworkState state) {
    command.apply(state);
    _stack.addLast(command);
    while (_stack.length > depth) {
      _stack.removeFirst();
    }
  }

  bool undo(ArtworkState state) {
    if (_stack.isEmpty) return false;
    _stack.removeLast().revert(state);
    return true;
  }

  void clear() => _stack.clear();
}
```

- [ ] **Step 5: `ColoringController` 호출부 맞추기**

`app/lib/coloring/coloring_controller.dart` 에서:

1. import 추가: `import '../core/artwork_state.dart';`
2. `final FillState _fills = FillState();` 를 지우고 `final ArtworkState _state = ArtworkState();` 로 바꾼다
3. `FillState get fills => _fills;` 를 `FillState get fills => _state.fills;` 로 바꾸고,
   `ArtworkState get state => _state;` 를 추가한다
4. `_fills` 를 쓰던 자리를 전부 바꾼다:
   - `_undo.push(..., _fills)` → `_undo.push(..., _state)`
   - `_undo.undo(_fills)` → `_undo.undo(_state)`
   - `_fills.clear()` → `_state.clear()`
   - `_fills.loadJson(...)` → `_state.fills.loadJson(...)`
   - `_fills.fillOf(id)` → `_state.fills.fillOf(id)`
   - `_fills.toJson()` → `_state.fills.toJson()`

- [ ] **Step 6: 전체 테스트와 분석 확인**

```bash
cd app && flutter test
cd app && flutter analyze
```

Expected: 전부 통과, `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add app
git commit -F - <<'MSG'
feat(app): 명령이 ArtworkState 하나를 받도록 확장하고 묶음 명령 추가

레이어마다 스택을 따로 두면 아이가 조작한 순서대로 되돌아가지 않는다.
지우개 한 손짓이 명령 여러 개를 만들므로 BatchCommand 가 필요하다.
MSG
```

---

### Task 6: 칠할 수 있는 영역 마스크

**Files:**
- Create: `app/lib/coloring/paintable_mask.dart`
- Test: `app/test/paintable_mask_test.dart`

**Interfaces:**
- Consumes: `RegionMap`·`kRegionFirstFillable` (`package:dohan_core/dohan_core.dart`)
- Produces: `Future<ui.Image> buildPaintableMask(RegionMap regions)` — `regionId >= 2` 인 픽셀만 불투명한 흰색, 나머지는 완전 투명

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/paintable_mask_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/paintable_mask.dart';

Future<List<int>> _alphaRow(ui.Image img) async {
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return [
    for (var x = 0; x < img.width; x++) bytes.getUint8(x * 4 + 3),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('칠할 수 있는 픽셀만 불투명하다', () async {
    // 0 = 선, 1 = 배경, 2·3 = 칠할 수 있는 영역
    final ids = Uint16List.fromList([0, 1, 2, 3, 0]);
    final mask = await buildPaintableMask(RegionMap(5, 1, ids));

    expect(await _alphaRow(mask), [0, 0, 255, 255, 0]);
  });

  test('크기가 인덱스맵과 같다', () async {
    final mask = await buildPaintableMask(
      RegionMap(7, 3, Uint16List(21)..fillRange(0, 21, 2)),
    );
    expect(mask.width, 7);
    expect(mask.height, 3);
  });

  test('16bit 영역 ID 도 칠할 수 있는 것으로 친다', () async {
    final ids = Uint16List.fromList([1, 300, 65535]);
    final mask = await buildPaintableMask(RegionMap(3, 1, ids));
    expect(await _alphaRow(mask), [0, 255, 255]);
  });

  test('전부 배경이면 전부 투명하다', () async {
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([1, 1, 1, 1])),
    );
    expect(await _alphaRow(mask), [0, 0, 0, 0]);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/paintable_mask_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/coloring/paintable_mask.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/coloring/paintable_mask.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';

/// 칠할 수 있는 픽셀만 불투명한 마스크를 만든다.
///
/// 상위 스펙 7.3 은 브러시를 합성할 때 셰이더가 픽셀마다 `regionId >= 2` 를
/// 확인하라고 하지만, 칠할 수 있는지 아닌지는 **도안마다 고정**이라 런타임에
/// 픽셀마다 물을 이유가 없다. 도안을 읽을 때 한 번 만들어두고 `BlendMode.dstIn`
/// 으로 한 번 블렌드하면 결과가 같다 — 설계 문서 3.1절.
///
/// 1024² 에서 7ms 걸린다(실측). 도안당 한 번이다.
Future<ui.Image> buildPaintableMask(RegionMap regions) {
  final n = regions.width * regions.height;
  final px = Uint8List(n * 4);
  for (var i = 0; i < n; i++) {
    if (regions.ids[i] >= kRegionFirstFillable) {
      final o = i * 4;
      px[o] = 255;
      px[o + 1] = 255;
      px[o + 2] = 255;
      px[o + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    px,
    regions.width,
    regions.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/paintable_mask_test.dart
```

Expected: PASS — 4개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -F - <<'MSG'
feat(app): 칠할 수 있는 영역 마스크 생성
MSG
```

---

### Task 7: 브러시 페인터 — 재생과 마스킹

**Files:**
- Create: `app/lib/coloring/brush_painter.dart`
- Test: `app/test/brush_painter_test.dart`

**Interfaces:**
- Consumes: `BrushState`·`Stroke`·`BrushKind` (Task 3), `buildPaintableMask` (Task 6)
- Produces: `class BrushPainter { static void paint(ui.Canvas canvas, ui.Rect bounds, BrushState brush, ui.Image? mask); static void drawStroke(ui.Canvas canvas, Stroke s) }`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/brush_painter_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/brush_painter.dart';
import 'package:kkumul/coloring/brush_state.dart';
import 'package:kkumul/coloring/paintable_mask.dart';

const _red = Color(0xFFFF0000);

Stroke _across(int w, {BrushKind kind = BrushKind.brush}) => Stroke(
      kind: kind,
      color: _red,
      width: 8,
      points: [const ui.Offset(0, 0.5), ui.Offset(w.toDouble(), 0.5)],
    );

/// [w] x 1 캔버스에 브러시 레이어만 그려 픽셀을 읽는다.
Future<List<List<int>>> _render(int w, BrushState brush, ui.Image? mask) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  BrushPainter.paint(
      canvas, ui.Rect.fromLTWH(0, 0, w.toDouble(), 1), brush, mask);
  final img = await rec.endRecording().toImage(w, 1);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return [
    for (var x = 0; x < w; x++)
      [
        bytes.getUint8(x * 4),
        bytes.getUint8(x * 4 + 1),
        bytes.getUint8(x * 4 + 2),
        bytes.getUint8(x * 4 + 3),
      ],
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('칠할 수 없는 픽셀에는 브러시가 남지 않는다', () async {
    // 왼쪽 4 = 칠할 수 있음, 오른쪽 4 = 선
    final mask = await buildPaintableMask(
      RegionMap(8, 1, Uint16List.fromList([2, 2, 2, 2, 0, 0, 0, 0])),
    );
    final brush = BrushState()..push(_across(8));

    final px = await _render(8, brush, mask);

    for (var x = 0; x < 4; x++) {
      expect(px[x][3], greaterThan(0), reason: '$x 번 픽셀은 칠해져야 한다');
    }
    for (var x = 4; x < 8; x++) {
      expect(px[x], [0, 0, 0, 0], reason: '$x 번 픽셀은 선이라 잘려야 한다');
    }
  });

  test('배경 위에도 남지 않는다', () async {
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([1, 1, 2, 2])),
    );
    final brush = BrushState()..push(_across(4));

    final px = await _render(4, brush, mask);

    expect(px[0], [0, 0, 0, 0]);
    expect(px[1], [0, 0, 0, 0]);
    expect(px[2][3], greaterThan(0));
  });

  test('영역 경계는 넘나든다', () async {
    // 2 와 3 은 다른 영역이지만 둘 다 칠할 수 있으므로 획이 이어져야 한다.
    // 상위 스펙 7.3 이 의도한 관대함이다.
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([2, 2, 3, 3])),
    );
    final brush = BrushState()..push(_across(4));

    final px = await _render(4, brush, mask);

    for (var x = 0; x < 4; x++) {
      expect(px[x][3], greaterThan(0), reason: '$x 번에서 끊기면 안 된다');
    }
  });

  test('지우개 획이 앞선 잉크를 지운다', () async {
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([2, 2, 2, 2])),
    );
    final brush = BrushState()
      ..push(_across(4))
      ..push(const Stroke(
        kind: BrushKind.eraser,
        color: _red,
        width: 8,
        points: [ui.Offset(2.5, 0.5), ui.Offset(4, 0.5)],
      ));

    final px = await _render(4, brush, mask);

    expect(px[0][3], greaterThan(0), reason: '지우지 않은 왼쪽은 남는다');
    expect(px[3], [0, 0, 0, 0], reason: '지운 오른쪽은 비어야 한다');
  });

  test('그리는 중인 획도 보인다', () async {
    final mask = await buildPaintableMask(
      RegionMap(4, 1, Uint16List.fromList([2, 2, 2, 2])),
    );
    final brush = BrushState()..live = _across(4);

    final px = await _render(4, brush, mask);

    expect(px[1][3], greaterThan(0), reason: '손가락을 떼기 전에도 그려져야 한다');
  });

  test('아무것도 없으면 아무것도 그리지 않는다', () async {
    final px = await _render(4, BrushState(), null);
    for (final p in px) {
      expect(p, [0, 0, 0, 0]);
    }
  });

  test('크레용은 붓보다 옅다', () async {
    final mask = await buildPaintableMask(
      RegionMap(2, 1, Uint16List.fromList([2, 2])),
    );
    final crayon = await _render(
        2, BrushState()..push(_across(2, kind: BrushKind.crayon)), mask);
    final brush = await _render(
        2, BrushState()..push(_across(2, kind: BrushKind.brush)), mask);

    expect(crayon[0][3], lessThan(brush[0][3]),
        reason: '겹쳐 그으면 진해지는 크레용 느낌');
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/brush_painter_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/coloring/brush_painter.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/coloring/brush_painter.dart`:

```dart
import 'dart:ui' as ui;

import 'brush_state.dart';

/// 브러시 레이어를 그린다.
///
/// 오프스크린 이미지에 누적하지 않고 매 프레임 스트로크 목록을 재생한다 —
/// 획 50개 × 점 100개 기록이 실측 2ms 라 프레임 예산(16.7ms) 안에 넉넉하다.
class BrushPainter {
  /// 브러시 레이어 한 겹을 [canvas] 에 합성한다.
  ///
  /// [mask] 는 칠할 수 있는 픽셀만 불투명한 이미지다. `dstIn` 으로 한 번
  /// 블렌드하면 선과 배경 위의 브러시가 잘려 나간다 — 상위 스펙 7.3 이
  /// 셰이더로 하라던 일과 결과가 같고 비용이 낮다(설계 문서 3.1절).
  static void paint(
    ui.Canvas canvas,
    ui.Rect bounds,
    BrushState brush,
    ui.Image? mask,
  ) {
    final live = brush.live;
    final base = brush.base;
    if (base == null && brush.strokes.isEmpty && live == null) return;

    // saveLayer 가 필요하다. 지우개의 BlendMode.clear 와 마스크의 dstIn 이
    // 브러시 레이어 안에서만 작용해야 하고, 밑에 깔린 채움 레이어를 건드리면
    // 안 된다.
    canvas.saveLayer(bounds, ui.Paint());

    if (base != null) {
      canvas.drawImage(base, ui.Offset.zero, ui.Paint());
    }
    for (final s in brush.strokes) {
      drawStroke(canvas, s);
    }
    if (live != null) {
      drawStroke(canvas, live);
    }
    if (mask != null) {
      canvas.drawImage(
        mask,
        ui.Offset.zero,
        ui.Paint()..blendMode = ui.BlendMode.dstIn,
      );
    }

    canvas.restore();
  }

  static void drawStroke(ui.Canvas canvas, Stroke s) {
    if (s.points.isEmpty) return;

    final paint = ui.Paint()
      ..strokeWidth = s.width
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..style = ui.PaintingStyle.stroke
      ..isAntiAlias = true;

    if (s.kind == BrushKind.eraser) {
      // 지우개는 색이 아니라 구멍이다. saveLayer 안에서만 뚫는다.
      paint.blendMode = ui.BlendMode.clear;
    } else {
      // 크레용은 살짝 비친다 — 겹쳐 그으면 진해지는 것이 실제 크레용에 가깝다.
      paint.color = s.kind == BrushKind.crayon
          ? s.color.withValues(alpha: 0.85)
          : s.color;
    }

    if (s.points.length == 1) {
      // 점 하나는 stroke 로 아무것도 그려지지 않는다. 원으로 찍는다.
      canvas.drawCircle(
        s.points.first,
        s.width / 2,
        ui.Paint()
          ..color = paint.color
          ..blendMode = paint.blendMode
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.fill,
      );
      return;
    }

    final path = ui.Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (final p in s.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}
```

`Color.withValues` 를 분석기가 모른다고 하면 (이 Flutter 버전에는 있을 것으로 보지만
확인하지 않았다) `ui.Color.fromARGB(217, (s.color.r * 255).round(), (s.color.g * 255).round(), (s.color.b * 255).round())`
로 바꾸고 **리포트에 적을 것.**

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/brush_painter_test.dart
```

Expected: PASS — 7개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 브러시 레이어 재생과 dstIn 마스킹"
```

---

### Task 8: 스티커 그림 10장

**Files:**
- Create: `app/tools/make_stickers.dart`
- Create: `app/assets/stickers/*.png` (스크립트가 만든다)
- Modify: `app/lib/coloring/sticker_state.dart` (`kStickerIds` 추가)
- Modify: `app/pubspec.yaml` (에셋 등록)
- Test: `app/test/sticker_assets_test.dart`

**Interfaces:**
- Consumes: `package:image`
- Produces: `const List<String> kStickerIds` (`sticker_state.dart` 안), `app/assets/stickers/<id>.png` 10장 (256×256 RGBA)

도안 샘플을 만든 `app/tools/make_sample_lineart.dart` 와 같은 패턴이다. 디자이너가 없으므로
빌드 타임 스크립트로 단순한 도형을 굽는다. 나중에 디자이너나 AI 생성물이 같은 경로의 파일을
바꿔 끼우면 코드는 그대로다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/sticker_assets_test.dart`:

```dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/sticker_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('스티커 열 개가 정해져 있다', () {
    expect(kStickerIds, hasLength(10));
    expect(kStickerIds.toSet(), hasLength(10), reason: '중복된 id 가 있다');
  });

  test('열 개 전부 에셋으로 실려 있다', () async {
    for (final id in kStickerIds) {
      final data = await rootBundle.load('assets/stickers/$id.png');
      expect(data.lengthInBytes, greaterThan(0), reason: id);
    }
  });

  test('서랍 두 줄에 들어가는 수다', () {
    // 320dp 화면에서 64dp 칸이 한 줄에 다섯. 상황별 영역이 128dp 이므로 두 줄.
    // 더 넣으면 스크롤이 필요하고, 스크롤되는 줄은 글 못 읽는 아이에게
    // 보이지 않는 것과 같다 — 계획 2 최종 리뷰가 잡은 바로 그 결함이다.
    expect(kStickerIds.length, lessThanOrEqualTo(10));
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/sticker_assets_test.dart
```

Expected: FAIL — `kStickerIds` 가 정의되지 않아 컴파일이 깨진다.

- [ ] **Step 3: `kStickerIds` 추가**

`app/lib/coloring/sticker_state.dart` 의 import 바로 아래에 추가한다:

```dart
/// 1단계 스티커 목록. 이 순서가 서랍에 보이는 순서다.
///
/// 열 개인 것은 화면 때문이다 — 320dp 에서 64dp 칸이 한 줄에 다섯이고
/// 상황별 영역이 두 줄이다. 더 넣으면 스크롤이 필요한데, 글을 못 읽는 아이에게
/// 스크롤되는 줄은 보이지 않는 것과 같다.
const List<String> kStickerIds = [
  'star-01',
  'heart-01',
  'flower-01',
  'dot-01',
  'diamond-01',
  'triangle-01',
  'moon-01',
  'ring-01',
  'cross-01',
  'cloud-01',
];
```

- [ ] **Step 4: 생성 스크립트 작성**

`app/tools/make_stickers.dart`:

```dart
// 스티커 그림 10장을 굽는다. 디자이너가 없으므로 도형을 수식으로 그린다.
//
// 실행: cd app && dart run tools/make_stickers.dart
//
// 라이브러리의 도형 그리기 API 를 쓰지 않고 픽셀마다 "안인가"를 판정한다.
// API 이름을 잘못 짚을 위험이 없고, 도형을 늘리기도 쉽다.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int kSize = 256;

/// 정규화 좌표(-1..1)에서 도형 안인지 판정한다.
typedef Shape = bool Function(double x, double y);

double _r(double x, double y) => math.sqrt(x * x + y * y);
double _theta(double x, double y) => math.atan2(y, x);

class _Sticker {
  final Shape shape;
  final int fill;
  const _Sticker(this.shape, this.fill);
}

final Map<String, _Sticker> _stickers = {
  'star-01': _Sticker((x, y) {
    final t = _theta(x, y) + math.pi / 2;
    final k = 5 * t / (2 * math.pi);
    final f = (k - k.floorToDouble()) * 2 - 1;
    return _r(x, y) <= 0.42 + 0.46 * (1 - f.abs());
  }, 0xF1BD45),
  'heart-01': _Sticker((x, y) {
    final px = x * 1.35;
    final py = -y * 1.35 + 0.25;
    final a = px * px + py * py - 1;
    return a * a * a - px * px * py * py * py <= 0;
  }, 0xEF7586),
  'flower-01': _Sticker(
    (x, y) => _r(x, y) <= 0.5 + 0.38 * math.cos(6 * _theta(x, y)).abs(),
    0x9E82CF,
  ),
  'dot-01': _Sticker((x, y) => _r(x, y) <= 0.85, 0x6CAEE0),
  'diamond-01': _Sticker((x, y) => x.abs() + y.abs() <= 0.9, 0x63B98B),
  'triangle-01': _Sticker(
    (x, y) => y <= 0.72 && (y + 0.72) >= 1.75 * x.abs(),
    0xEF8A45,
  ),
  'moon-01': _Sticker(
    (x, y) => _r(x, y) <= 0.85 && _r(x - 0.42, y) > 0.7,
    0xF1BD45,
  ),
  'ring-01': _Sticker(
    (x, y) => _r(x, y) <= 0.85 && _r(x, y) >= 0.48,
    0xEF7586,
  ),
  'cross-01': _Sticker(
    (x, y) => (x.abs() <= 0.28 && y.abs() <= 0.85) ||
        (y.abs() <= 0.28 && x.abs() <= 0.85),
    0x6CAEE0,
  ),
  'cloud-01': _Sticker(
    (x, y) =>
        _r(x + 0.38, y - 0.12) <= 0.4 ||
        _r(x - 0.38, y - 0.12) <= 0.4 ||
        _r(x, y - 0.3) <= 0.5 ||
        (y >= -0.12 && y <= 0.3 && x.abs() <= 0.45),
    0xAED2EE,
  ),
};

int _darken(int rgb) {
  final r = (((rgb >> 16) & 0xFF) * 0.55).round();
  final g = (((rgb >> 8) & 0xFF) * 0.55).round();
  final b = ((rgb & 0xFF) * 0.55).round();
  return (r << 16) | (g << 8) | b;
}

void main() {
  final dir = Directory('assets/stickers');
  dir.createSync(recursive: true);

  for (final entry in _stickers.entries) {
    final s = entry.value;
    final outline = _darken(s.fill);
    final im = img.Image(width: kSize, height: kSize, numChannels: 4);

    for (var py = 0; py < kSize; py++) {
      for (var px = 0; px < kSize; px++) {
        final nx = (px + 0.5) / kSize * 2 - 1;
        final ny = (py + 0.5) / kSize * 2 - 1;
        if (!s.shape(nx, ny)) continue;
        // 살짝 키운 좌표에서 벗어나면 가장자리다 = 테두리
        final c = s.shape(nx * 1.1, ny * 1.1) ? s.fill : outline;
        im.setPixelRgba(px, py, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, 255);
      }
    }

    final path = '${dir.path}/${entry.key}.png';
    File(path).writeAsBytesSync(img.encodePng(im));
    stdout.writeln('wrote $path');
  }
}
```

- [ ] **Step 5: 스크립트 실행**

```bash
cd app && dart run tools/make_stickers.dart
ls assets/stickers/
```

Expected: `wrote assets/stickers/...` 열 줄, `ls` 에 PNG 10개.
**10개가 아니거나 스크립트가 던지면 멈추고 보고할 것.**

- [ ] **Step 6: 에셋 등록**

`app/pubspec.yaml` 의 `flutter:` → `assets:` 목록에 기존 도안 줄 아래로 한 줄 추가한다:

```yaml
    - assets/stickers/
```

- [ ] **Step 7: 테스트 통과 확인**

```bash
cd app && flutter test test/sticker_assets_test.dart
cd app && flutter analyze
```

Expected: PASS — 3개 테스트 통과, `No issues found!`

- [ ] **Step 8: 커밋**

```bash
git add app
git commit -m "feat(app): 스티커 그림 10장과 생성 스크립트"
```

---

### Task 9: 연령 설정

**Files:**
- Create: `app/lib/settings/settings.dart`
- Test: `app/test/settings_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum AgeMode { toddler, child }`
  - `class Settings { final AgeMode ageMode; const Settings({AgeMode ageMode = AgeMode.toddler}); Map<String,dynamic> toJson(); factory Settings.fromJson(Map<String,dynamic>) }`
  - `class SettingsStore { SettingsStore(Directory root); Future<Settings> load(); Future<void> save(Settings) }`

`내 정보` 화면은 계획 5 다. 여기서는 읽고 쓰는 계층까지만 만들고, 시험은 파일을 직접 고쳐서 한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/settings_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/settings/settings.dart';

void main() {
  late Directory root;
  late SettingsStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_set_');
    store = SettingsStore(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('아무것도 없으면 유아 모드다', () async {
    expect((await store.load()).ageMode, AgeMode.toddler,
        reason: '상위 스펙 9장의 기본값');
  });

  test('저장한 것을 다시 읽는다', () async {
    await store.save(const Settings(ageMode: AgeMode.child));
    expect((await store.load()).ageMode, AgeMode.child);
  });

  test('내용이 깨졌으면 기본값으로 돌아간다', () async {
    File('${root.path}/settings.json').writeAsStringSync('{{{');
    expect((await store.load()).ageMode, AgeMode.toddler);
  });

  test('모르는 연령 값이면 기본값으로 돌아간다', () async {
    File('${root.path}/settings.json').writeAsStringSync('{"ageMode":"우주인"}');
    expect((await store.load()).ageMode, AgeMode.toddler);
  });

  test('JSON 으로 왕복한다', () {
    const s = Settings(ageMode: AgeMode.child);
    expect(Settings.fromJson(s.toJson()).ageMode, AgeMode.child);
  });

  test('읽기 자체가 실패하면 던진다', () async {
    // 파일 자리에 디렉터리를 놓으면 읽기가 실패한다. 이때 조용히 기본값으로
    // 돌아가면 다음 save 가 멀쩡할 수도 있는 설정을 덮어쓴다 — 계획 2 의
    // ArtworkRepository.load 와 같은 원칙이다.
    Directory('${root.path}/settings.json').createSync();
    expect(store.load(), throwsA(isA<FileSystemException>()));
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/settings_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/settings/settings.dart'`

- [ ] **Step 3: 구현 작성**

`app/lib/settings/settings.dart`:

```dart
import 'dart:convert';
import 'dart:io';

/// 연령대. 상위 스펙 9장.
enum AgeMode { toddler, child }

/// 보호자가 정하는 설정.
class Settings {
  final AgeMode ageMode;

  const Settings({this.ageMode = AgeMode.toddler});

  Map<String, dynamic> toJson() => {'ageMode': ageMode.name};

  factory Settings.fromJson(Map<String, dynamic> j) {
    final name = j['ageMode'];
    for (final m in AgeMode.values) {
      if (m.name == name) return Settings(ageMode: m);
    }
    // 모르는 값이면 기본값. 설정 하나가 이상하다고 앱이 안 뜨면 안 된다.
    return const Settings();
  }
}

/// `settings.json` 하나를 읽고 쓴다.
class SettingsStore {
  final Directory root;

  SettingsStore(this.root);

  File get _file => File('${root.path}/settings.json');

  /// 없거나 내용이 깨졌으면 기본값.
  ///
  /// 다만 **읽기 자체가 실패한 경우(권한·잠김·디스크)는 던진다.** 그것을
  /// 기본값으로 뭉개면 다음 `save` 가 멀쩡할 수도 있는 설정을 덮어쓴다 —
  /// 계획 2 의 `ArtworkRepository.load` 와 같은 원칙이다. 부르는 쪽이 잡는다.
  Future<Settings> load() async {
    final String text;
    try {
      text = await _file.readAsString();
    } on PathNotFoundException {
      return const Settings();
    }

    try {
      return Settings.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on FormatException {
      return const Settings();
    } on TypeError {
      return const Settings();
    }
  }

  Future<void> save(Settings settings) async {
    await root.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_file.path);
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/settings_test.dart
```

Expected: PASS — 6개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 연령 설정 읽기와 쓰기"
```

---

### Task 10: 세 파일 저장과 굽지 않는 자동 저장

**Files:**
- Modify: `app/lib/gallery/artwork_repository.dart`
- Modify: `app/lib/gallery/autosave.dart`
- Modify: `app/test/artwork_repository_test.dart` (기존 9개는 그대로 두고 추가)
- Modify: `app/test/autosave_test.dart` (기존 6개는 그대로 두고 추가)

**Interfaces:**
- Consumes: `Sticker` (Task 4)
- Produces:
  - `ArtworkRepository.save(Artwork artwork, {List<Sticker> stickers = const [], Uint8List? brushPng})` — `brushPng == null` 이면 `brush.png` 를 **건드리지 않는다**
  - `ArtworkRepository.loadStickers(String id) → Future<List<Sticker>>`
  - `ArtworkRepository.loadBrushPng(String id) → Future<Uint8List?>`
  - `typedef BrushBaker = Future<Uint8List?> Function();`
  - `Autosave.schedule(Artwork artwork, {List<Sticker> stickers = const [], int brushRevision = 0, BrushBaker? bakeBrush})`

**왜 이렇게 하는가**: `brush.png` 한 번 굽는 데 실측 53ms(래스터화 14 + PNG 39)다. 자동 저장은
1초 디바운스마다 돈다. 아이가 계속 그리는 동안 매초 그걸 하면 눈에 보이는 끊김이 된다.
그래서 **바뀌었을 때만** 굽는다. 채움만 바꾸는 아이(유아 모드가 정확히 그렇다)는 이 비용을
한 번도 내지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성 (저장소)**

`app/test/artwork_repository_test.dart` 의 `main()` 안, 기존 테스트들 **뒤에** 추가한다.
파일 상단 import 에 `import 'dart:typed_data';` 와
`import 'package:kkumul/coloring/sticker_state.dart';` 를 추가한다.

```dart
  test('스티커를 따로 저장하고 읽는다', () async {
    await repo.save(
      art(),
      stickers: [
        Sticker(instanceId: 'a', stickerId: 'star-01', x: 10, y: 20),
      ],
    );

    final back = await repo.loadStickers('a1');
    expect(back, hasLength(1));
    expect(back.first.stickerId, 'star-01');
    expect(back.first.x, 10);
  });

  test('스티커가 없으면 파일도 없고 빈 목록을 준다', () async {
    await repo.save(art());
    expect(await repo.loadStickers('a1'), isEmpty);
    expect(File('${root.path}/artworks/a1/stickers.json').existsSync(), isFalse);
  });

  test('브러시 PNG 를 주면 쓰고 안 주면 건드리지 않는다', () async {
    final png = Uint8List.fromList([1, 2, 3, 4]);
    await repo.save(art(), brushPng: png);
    expect(await repo.loadBrushPng('a1'), png);

    // 두 번째 저장은 브러시를 안 준다 — 기존 파일이 그대로 있어야 한다.
    await repo.save(art());
    expect(await repo.loadBrushPng('a1'), png,
        reason: 'null 은 "지워라"가 아니라 "건드리지 마라"다');
  });

  test('브러시가 없으면 null 이다', () async {
    await repo.save(art());
    expect(await repo.loadBrushPng('a1'), isNull);
  });

  test('브러시가 깨져도 채움과 스티커는 살아난다', () async {
    await repo.save(
      art(),
      stickers: [Sticker(instanceId: 'a', stickerId: 'star-01', x: 1, y: 2)],
      brushPng: Uint8List.fromList([9, 9]),
    );
    // stickers.json 만 망가뜨린다
    File('${root.path}/artworks/a1/stickers.json').writeAsStringSync('[[[');

    expect(await repo.load('a1'), isNotNull, reason: '채움은 멀쩡해야 한다');
    expect(await repo.loadStickers('a1'), isEmpty, reason: '깨진 스티커는 버린다');
    expect(await repo.loadBrushPng('a1'), isNotNull);
  });
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/artwork_repository_test.dart
```

Expected: FAIL — `No named parameter with the name 'stickers'` / `loadStickers` 가 없다

- [ ] **Step 3: 저장소 수정**

`app/lib/gallery/artwork_repository.dart`:

1. 상단 import 에 추가:

```dart
import 'dart:typed_data';

import '../coloring/sticker_state.dart';
```

2. `_fileFor` 아래에 파일 경로 두 개를 추가한다:

```dart
  File _stickersFileFor(String id) => File('${_dirFor(id).path}/stickers.json');

  File _brushFileFor(String id) => File('${_dirFor(id).path}/brush.png');
```

3. `save` 를 통째로 바꾼다:

```dart
  /// 작품을 쓴다. 임시 파일에 쓰고 rename 해서, 쓰는 도중 앱이 죽어도
  /// 반쯤 쓰인 파일이 남지 않게 한다.
  ///
  /// [brushPng] 가 `null` 이면 `brush.png` 를 **건드리지 않는다.** "지워라"가
  /// 아니라 "바뀐 게 없다"는 뜻이다 — 굽는 데 53ms 가 들어서, 바뀌지 않았으면
  /// 아예 만들지 않고 여기까지 오지 않는다.
  ///
  /// rename 은 파일 하나 안에서만 원자적이다. 셋을 연달아 쓰다 앱이 죽으면
  /// 레이어마다 마지막 1초가 다르게 남을 수 있는데, 그것은 파일이 깨진 것이
  /// 아니라 "방금 그은 획 하나가 없는" 상태다. 폴더 단위 원자화는 그 복잡도를
  /// 낼 값이 아니라고 판단했다.
  Future<void> save(
    Artwork artwork, {
    List<Sticker> stickers = const [],
    Uint8List? brushPng,
  }) async {
    final dir = _dirFor(artwork.id);
    await dir.create(recursive: true);

    final tmp = File('${dir.path}/artwork.json.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(artwork.toJson()),
      flush: true,
    );
    await tmp.rename(_fileFor(artwork.id).path);

    final stickersFile = _stickersFileFor(artwork.id);
    if (stickers.isEmpty) {
      if (stickersFile.existsSync()) await stickersFile.delete();
    } else {
      final stmp = File('${dir.path}/stickers.json.tmp');
      await stmp.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert([for (final s in stickers) s.toJson()]),
        flush: true,
      );
      await stmp.rename(stickersFile.path);
    }

    if (brushPng != null) {
      final btmp = File('${dir.path}/brush.png.tmp');
      await btmp.writeAsBytes(brushPng, flush: true);
      await btmp.rename(_brushFileFor(artwork.id).path);
    }
  }
```

4. `load` 아래에 읽기 두 개를 추가한다:

```dart
  /// 스티커 목록. 없거나 내용이 깨졌으면 빈 목록.
  ///
  /// 파일 셋을 독립적으로 취급한다 — 스티커가 깨져도 채움과 브러시는 살아난다.
  Future<List<Sticker>> loadStickers(String id) async {
    final String text;
    try {
      text = await _stickersFileFor(id).readAsString();
    } on PathNotFoundException {
      return const [];
    }

    try {
      final list = jsonDecode(text) as List<dynamic>;
      return [
        for (final e in list) Sticker.fromJson(e as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  /// 구운 브러시 레이어. 없으면 null.
  Future<Uint8List?> loadBrushPng(String id) async {
    try {
      return await _brushFileFor(id).readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }
```

- [ ] **Step 4: 저장소 테스트 통과 확인**

```bash
cd app && flutter test test/artwork_repository_test.dart
```

Expected: PASS — 14개 테스트 통과 (기존 9 + 새 5)

- [ ] **Step 5: 실패하는 테스트 작성 (자동 저장)**

`app/test/autosave_test.dart` 의 `main()` 안, 기존 테스트들 **뒤에** 추가한다.
상단 import 에 `import 'dart:typed_data';` 와
`import 'package:kkumul/coloring/sticker_state.dart';` 를 추가한다.

```dart
  test('브러시가 바뀌지 않으면 굽지 않는다', () async {
    // 굽는 데 53ms 가 든다. 채움만 바꾸는 아이는 이 비용을 내면 안 된다.
    var baked = 0;
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    Future<Uint8List?> bake() async {
      baked++;
      return Uint8List.fromList([1]);
    }

    auto.schedule(art(0xFF111111), brushRevision: 7, bakeBrush: bake);
    await auto.flush();
    expect(baked, 1, reason: '처음에는 한 번 굽는다');

    auto.schedule(art(0xFF222222), brushRevision: 7, bakeBrush: bake);
    await auto.flush();
    expect(baked, 1, reason: '개정 번호가 같으면 다시 굽지 않는다');

    auto.schedule(art(0xFF333333), brushRevision: 8, bakeBrush: bake);
    await auto.flush();
    expect(baked, 2, reason: '바뀌었으면 굽는다');
  });

  test('굽는 함수를 안 주면 부르지 않는다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    auto.schedule(art(0xFF444444));
    await auto.flush();

    expect(auto.saveCount, 1);
    expect(await repo.loadBrushPng('a1'), isNull);
  });

  test('스티커도 함께 쓴다', () async {
    final auto = Autosave(
      repository: repo,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(auto.dispose);

    auto.schedule(
      art(0xFF555555),
      stickers: [Sticker(instanceId: 'a', stickerId: 'star-01', x: 5, y: 6)],
    );
    await auto.flush();

    expect(await repo.loadStickers('a1'), hasLength(1));
  });
```

- [ ] **Step 6: 테스트 실패 확인**

```bash
cd app && flutter test test/autosave_test.dart
```

Expected: FAIL — `No named parameter with the name 'brushRevision'`

- [ ] **Step 7: 자동 저장 수정**

`app/lib/gallery/autosave.dart`:

1. 상단 import 에 추가:

```dart
import 'dart:typed_data';

import '../coloring/sticker_state.dart';
```

2. 파일 맨 위(클래스 밖)에 추가:

```dart
/// 브러시 레이어를 PNG 로 굽는 함수. 실제로 쓸 때 **한 번만** 불린다.
typedef BrushBaker = Future<Uint8List?> Function();
```

3. `Autosave` 안의 `Artwork? _pending;` 을 아래로 바꾼다:

```dart
  _Pending? _pending;

  /// 마지막으로 실제로 구워서 쓴 브러시 개정 번호.
  int? _writtenBrushRevision;
```

4. `schedule` 을 바꾼다:

```dart
  void schedule(
    Artwork artwork, {
    List<Sticker> stickers = const [],
    int brushRevision = 0,
    BrushBaker? bakeBrush,
  }) {
    if (_disposed) return;
    _pending = _Pending(artwork, stickers, brushRevision, bakeBrush);
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush());
    });
  }
```

5. `_writeOnce` 를 바꾼다:

```dart
  Future<void> _writeOnce() async {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    try {
      // 브러시를 굽는 데 실측 53ms 다. 마지막으로 쓴 뒤로 획이 바뀌지 않았으면
      // 아예 만들지 않고, 저장소도 brush.png 를 건드리지 않는다.
      Uint8List? png;
      final bake = pending.bakeBrush;
      if (bake != null && pending.brushRevision != _writtenBrushRevision) {
        png = await bake();
      }

      await repository.save(
        pending.artwork,
        stickers: pending.stickers,
        brushPng: png,
      );

      if (png != null) _writtenBrushRevision = pending.brushRevision;
      _saveCount++;
    } on Object catch (error) {
      // 새로 예약된 것이 있으면 그것이 더 새것이므로 덮지 않는다.
      if (!_disposed) _pending ??= pending;
      debugPrint('작품 자동 저장 실패 — 다음 저장에서 다시 시도한다: $error');
    }
  }
```

6. 파일 맨 아래에 추가:

```dart
/// 아직 쓰지 않은 한 벌.
class _Pending {
  final Artwork artwork;
  final List<Sticker> stickers;
  final int brushRevision;
  final BrushBaker? bakeBrush;

  const _Pending(
    this.artwork,
    this.stickers,
    this.brushRevision,
    this.bakeBrush,
  );
}
```

`dispose()` 안의 `_pending = null;` 은 그대로 둔다.

- [ ] **Step 8: 전체 테스트와 분석 확인**

```bash
cd app && flutter test
cd app && flutter analyze
```

Expected: 전부 통과, `No issues found!`
`coloring_controller.dart` 가 `autosave.schedule(artwork)` 를 그대로 부르는데, 새 인자가
전부 기본값이 있으므로 고칠 것이 없다.

- [ ] **Step 9: 커밋**

```bash
git add app
git commit -m "feat(app): 스티커와 브러시를 따로 저장하고, 바뀌었을 때만 굽는다"
```

---

### Task 11: 컨트롤러 — 도구와 색 고르기

**Files:**
- Modify: `app/lib/coloring/coloring_controller.dart`
- Modify: `app/lib/ui/coloring_screen.dart` (호출부만)
- Test: `app/test/coloring_controller_test.dart` (기존 13개는 그대로 두고 추가)

**Interfaces:**
- Consumes: `Shade`·`paletteShades` (Task 1), `AgeMode` (Task 9)
- Produces:
  - `enum ToolKind { bucket, crayon, brush, eraser, sticker }`
  - `ColoringController({required DohanSource source, required Autosave autosave, AgeMode ageMode = AgeMode.toddler})`
  - getter/setter `AgeMode ageMode`
  - `ToolKind get tool; void selectTool(ToolKind)`
  - `Shade get shade; void cycleShade()`
  - `int get colorIndex; void pickColorIndex(int)`
  - `Color get selectedColor` (기존 이름 유지)
  - `bool get canUndo` — 유아 모드의 연속 한 번 제한을 반영한다

`pickColor(Color)` 는 **없앤다.** 색이 아니라 자리를 고르는 것이 팔레트의 계약이다(Task 2).

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/coloring_controller_test.dart` 의 `main()` 안, 기존 테스트들 뒤에 추가한다.
상단 import 에 `import 'package:kkumul/settings/settings.dart';` 와
`import 'package:kkumul/ui/palette_shades.dart';` 를 추가한다.

```dart
  test('처음 도구는 양동이다', () {
    expect(c.tool, ToolKind.bucket);
  });

  test('도구를 고르면 바뀐다', () {
    c.selectTool(ToolKind.crayon);
    expect(c.tool, ToolKind.crayon);
  });

  test('색은 자리로 고르고 명도가 곱해진다', () {
    c.pickColorIndex(4);
    expect(c.colorIndex, 4);
    expect(c.selectedColor, paletteShades[Shade.base]![4]);
  });

  test('명도를 누르면 고른 자리는 그대로고 색만 바뀐다', () {
    c.pickColorIndex(4);
    c.cycleShade();

    expect(c.colorIndex, 4, reason: '아이가 고른 자리는 유지된다');
    expect(c.shade, Shade.dark, reason: 'base 다음은 dark');
    expect(c.selectedColor, paletteShades[Shade.dark]![4]);
  });

  test('명도는 한 바퀴 돈다', () {
    c.cycleShade();
    c.cycleShade();
    expect(c.shade, Shade.light);
    c.cycleShade();
    expect(c.shade, Shade.base);
  });

  test('양동이가 아니면 탭해도 칠해지지 않는다', () {
    c.selectTool(ToolKind.crayon);
    expect(c.tapAt(const Offset(0.5, 0.5)), isFalse,
        reason: '크레용은 끌어서 그리는 도구다');
    expect(c.fills.filledCount, 0);
  });

  test('유아 모드는 연속 한 번만 되돌린다', () {
    c.ageMode = AgeMode.toddler;
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.tapAt(const Offset(3.5, 0.5));

    expect(c.undo(), isTrue);
    expect(c.undo(), isFalse, reason: '상위 스펙 9장 — 유아는 한 단계');
    expect(c.canUndo, isFalse, reason: '버튼도 꺼져야 한다');
  });

  test('유아 모드도 새로 칠하면 다시 한 번 되돌릴 수 있다', () {
    c.ageMode = AgeMode.toddler;
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.undo();
    expect(c.undo(), isFalse);

    c.tapAt(const Offset(3.5, 0.5));
    expect(c.canUndo, isTrue);
    expect(c.undo(), isTrue);
  });

  test('아동 모드는 계속 되돌린다', () {
    c.ageMode = AgeMode.child;
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.tapAt(const Offset(3.5, 0.5));

    expect(c.undo(), isTrue);
    expect(c.undo(), isTrue);
    expect(c.undo(), isFalse, reason: '더 없어서 false 다');
  });
```

`setUp` 의 컨트롤러 생성에 `ageMode: AgeMode.child` 를 넣는다 — 기존 13개 테스트가
되돌리기를 여러 번 쓰기 때문이다. 유아 제한은 위 두 테스트가 직접 켠다.

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/coloring_controller_test.dart
```

Expected: FAIL — `ToolKind` 가 없고 `pickColorIndex` 가 없다

- [ ] **Step 3: 컨트롤러 수정**

`app/lib/coloring/coloring_controller.dart`:

1. import 추가:

```dart
import '../settings/settings.dart';
import '../ui/palette_shades.dart';
```

2. 파일 맨 위(클래스 밖)에 추가:

```dart
/// 도구 다섯 가지. 상위 스펙 9장의 아동 모드 도구 목록이다.
enum ToolKind { bucket, crayon, brush, eraser, sticker }
```

3. 필드를 바꾼다. `Color _selected = const Color(0xFFEF7586);` 를 지우고:

```dart
  AgeMode ageMode;

  ToolKind _tool = ToolKind.bucket;
  Shade _shade = Shade.base;
  int _colorIndex = 0;

  /// 유아 모드의 "연속 한 번" 제한을 세는 값. 새로 무언가를 하면 0 이 된다.
  int _undosSinceChange = 0;
```

4. 생성자를 바꾼다:

```dart
  ColoringController({
    required this.source,
    required this.autosave,
    this.ageMode = AgeMode.toddler,
  });
```

5. getter 들을 바꾼다. `Color get selectedColor => _selected;` 를 지우고:

```dart
  ToolKind get tool => _tool;
  Shade get shade => _shade;
  int get colorIndex => _colorIndex;

  /// 고른 자리와 명도가 만나는 색.
  Color get selectedColor => paletteShades[_shade]![_colorIndex];

  /// 유아 모드는 연속 한 번만 되돌린다(상위 스펙 9장). 내부 스택은 동일하다.
  bool get canUndo =>
      _undo.canUndo &&
      !(ageMode == AgeMode.toddler && _undosSinceChange >= 1);
```

6. `pickColor` 를 아래 셋으로 바꾼다:

```dart
  void selectTool(ToolKind next) {
    if (_tool == next) return;
    _tool = next;
    notifyListeners();
  }

  /// 앱바의 명도 버튼. 밝게 → 기본 → 어둡게 → 밝게.
  ///
  /// 고른 **자리**는 그대로 두고 색만 갈아끼운다. 아이가 고른 것은 "네 번째
  /// 크레용"이지 특정 hex 가 아니다.
  void cycleShade() {
    _shade = _shade.next;
    notifyListeners();
  }

  void pickColorIndex(int index) {
    if (index < 0 || index >= paletteShades[_shade]!.length) return;
    _colorIndex = index;
    notifyListeners();
  }
```

7. `tapAt` 첫머리에 도구 검사를 넣는다. `final dohan = _dohan;` 바로 위에:

```dart
    // 양동이일 때만 탭으로 칠한다. 크레용·붓·지우개는 끌어서 쓰는 도구고,
    // 스티커는 서랍에서 고른다.
    if (_tool != ToolKind.bucket) return false;
```

8. `undo()` 와 저장 예약을 바꾼다:

```dart
  bool undo() {
    if (!canUndo) return false;
    if (!_undo.undo(_state)) return false;
    _undosSinceChange++;
    _scheduleSave();
    notifyListeners();
    return true;
  }
```

그리고 `tapAt` 안의 `_scheduleSave(); notifyListeners();` 앞에 `_undosSinceChange = 0;` 을
넣는다 — 새로 칠했으면 되돌리기 예산이 되살아난다.

- [ ] **Step 4: 화면 호출부 맞추기**

`app/lib/ui/coloring_screen.dart` 의 `PaletteBar` 호출에서 `c.pickColor(...)` 줄을 지우고:

```dart
              onPickIndex: (i) {
                setState(() => _paletteIndex = i);
                c.pickColorIndex(i);
              },
```

- [ ] **Step 5: 전체 테스트와 분석 확인**

```bash
cd app && flutter test
cd app && flutter analyze
```

Expected: 전부 통과, `No issues found!`

- [ ] **Step 6: 커밋**

```bash
git add app
git commit -m "feat(app): 도구 선택과 명도 순환, 유아 되돌리기 제한"
```

---

### Task 12: 컨트롤러 — 브러시 획과 지우개

**Files:**
- Modify: `app/lib/coloring/coloring_controller.dart`
- Test: `app/test/coloring_controller_test.dart` (추가)

**Interfaces:**
- Consumes: `BrushState`·`Stroke`·굵기 상수 (Task 3), `buildPaintableMask` (Task 6), `BrushPainter` (Task 7), `BrushBaker` (Task 10)
- Produces:
  - `void beginStroke(Offset canvasPoint)`, `void extendStroke(Offset)`, `void endStroke()`
  - `ui.Image? get paintableMask`
  - `ArtworkState get state`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/coloring_controller_test.dart` 에 추가한다. 상단 import 에
`import 'package:kkumul/coloring/brush_state.dart';` 를 추가한다.

```dart
  test('크레용으로 끌면 획이 남는다', () {
    c.selectTool(ToolKind.crayon);
    c.beginStroke(const Offset(0.5, 0.5));
    c.extendStroke(const Offset(3.5, 0.5));
    c.endStroke();

    expect(c.state.brush.strokes, hasLength(1));
    expect(c.state.brush.strokes.first.kind, BrushKind.crayon);
    expect(c.state.brush.live, isNull, reason: '손을 떼면 live 가 비워진다');
  });

  test('그리는 중에는 live 에 들어 있다', () {
    c.selectTool(ToolKind.brush);
    c.beginStroke(const Offset(0.5, 0.5));
    expect(c.state.brush.live, isNotNull);
    expect(c.state.brush.strokes, isEmpty, reason: '아직 명령이 아니다');
    c.endStroke();
    expect(c.state.brush.strokes, hasLength(1));
  });

  test('획을 되돌리면 사라진다', () {
    c.selectTool(ToolKind.crayon);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();

    expect(c.undo(), isTrue);
    expect(c.state.brush.strokes, isEmpty);
  });

  test('너무 촘촘한 점은 버린다', () {
    // 점이 촘촘해도 그림은 달라지지 않고 덮임 판정만 느려진다.
    c.selectTool(ToolKind.brush);
    c.beginStroke(const Offset(0, 0));
    c.extendStroke(const Offset(1, 0));
    c.extendStroke(const Offset(2, 0));
    c.endStroke();

    expect(c.state.brush.strokes.first.points, hasLength(1),
        reason: '4px 미만은 버린다');
  });

  test('양동이일 때는 끌어도 획이 생기지 않는다', () {
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();
    expect(c.state.brush.strokes, isEmpty);
  });

  test('지우개로 칠한 영역을 문지르면 색이 벗겨진다', () {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    expect(c.fills.fillOf(2), isNotNull);

    c.selectTool(ToolKind.eraser);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();

    expect(c.fills.fillOf(2), isNull);
  });

  test('지우개 한 손짓은 되돌리기 한 번에 전부 돌아온다', () {
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));
    c.tapAt(const Offset(3.5, 0.5));
    expect(c.fills.filledCount, 2);

    c.selectTool(ToolKind.eraser);
    c.beginStroke(const Offset(0.5, 0.5));
    c.extendStroke(const Offset(3.5, 0.5));
    c.endStroke();
    expect(c.fills.filledCount, 0);

    expect(c.undo(), isTrue);
    expect(c.fills.filledCount, 2, reason: '묶음이므로 한 번에 둘 다 돌아온다');
  });

  test('브러시 잉크가 있는 자리는 채움을 벗기지 않는다', () {
    // "손가락 밑의 맨 위 것을 지운다" — 잉크가 위에 있으면 잉크만 지운다.
    c.pickColorIndex(0);
    c.tapAt(const Offset(0.5, 0.5));

    c.selectTool(ToolKind.crayon);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();

    c.selectTool(ToolKind.eraser);
    c.beginStroke(const Offset(0.5, 0.5));
    c.endStroke();

    expect(c.fills.fillOf(2), isNotNull,
        reason: '잉크가 덮고 있었으므로 채움은 남는다');
  });

  test('도안을 열면 마스크가 만들어진다', () {
    expect(c.paintableMask, isNotNull);
    expect(c.paintableMask!.width, 4, reason: '가짜 도안이 4x2 다');
  });
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/coloring_controller_test.dart
```

Expected: FAIL — `beginStroke` 가 없다

- [ ] **Step 3: 컨트롤러 수정**

`app/lib/coloring/coloring_controller.dart`:

1. import 추가:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'brush_painter.dart';
import 'brush_state.dart';
import 'paintable_mask.dart';
```

2. 필드 추가:

```dart
  ui.Image? _mask;

  /// 이번 지우개 손짓에서 벗길 영역과 그 이전 색.
  final Map<int, Color?> _erasing = {};
```

3. getter 추가:

```dart
  ArtworkState get state => _state;

  /// 칠할 수 있는 픽셀만 불투명한 마스크. 브러시 합성에 쓴다.
  ui.Image? get paintableMask => _mask;
```

4. `open()` 안, `_dohan = dohan;` **바로 뒤에** 마스크 생성을 넣는다:

```dart
    _mask?.dispose();
    _mask = await buildPaintableMask(dohan.regions);
```

(생성은 1024² 에서 7ms 다. 도안당 한 번이다.)

5. 스트로크 세 개와 도우미를 `undo()` 앞에 추가한다:

```dart
  double get _strokeWidth => switch (_tool) {
        ToolKind.crayon => kCrayonWidth,
        ToolKind.brush => kBrushWidth,
        ToolKind.eraser => kEraserWidth,
        _ => kCrayonWidth,
      };

  BrushKind? get _strokeKind => switch (_tool) {
        ToolKind.crayon => BrushKind.crayon,
        ToolKind.brush => BrushKind.brush,
        ToolKind.eraser => BrushKind.eraser,
        _ => null,
      };

  void beginStroke(Offset canvasPoint) {
    final kind = _strokeKind;
    if (kind == null || _dohan == null) return;

    _erasing.clear();
    _state.brush.live = Stroke(
      kind: kind,
      color: selectedColor,
      width: _strokeWidth,
      points: [canvasPoint],
    );
    _collectErase(canvasPoint);
    notifyListeners();
  }

  void extendStroke(Offset canvasPoint) {
    final live = _state.brush.live;
    if (live == null) return;
    // 점이 촘촘해도 그림은 달라지지 않고 덮임 판정만 느려진다.
    if ((live.points.last - canvasPoint).distance < 4) return;
    live.points.add(canvasPoint);
    _collectErase(canvasPoint);
    notifyListeners();
  }

  void endStroke() {
    final live = _state.brush.live;
    if (live == null) return;
    _state.brush.live = null;

    final commands = <Command>[StrokeCommand(live)];
    for (final e in _erasing.entries) {
      commands.add(FillCommand(regionId: e.key, before: e.value, after: null));
    }
    _erasing.clear();

    // 지우개 한 손짓이 획 하나와 채움 여러 개를 만들 수 있다. 아이는 되돌리기
    // 한 번에 그 손짓 전체가 돌아오기를 기대한다.
    _undo.push(
      commands.length == 1 ? commands.first : BatchCommand(commands),
      _state,
    );
    _undosSinceChange = 0;
    _scheduleSave();
    notifyListeners();
  }

  /// 지우개가 지나간 자리에서 벗길 채움을 모은다.
  ///
  /// 브러시 잉크가 그 점을 덮고 있으면 채움은 건드리지 않는다 — "손가락 밑의
  /// 맨 위 것"을 지우는 것이므로, 잉크가 위에 있으면 잉크만 지워진다.
  void _collectErase(Offset p) {
    if (_tool != ToolKind.eraser) return;
    final dohan = _dohan;
    if (dohan == null) return;
    if (_state.brush.hasInkAt(p)) return;

    final id = regionAt(dohan.regions, p);
    if (id < kRegionFirstFillable) return;
    if (_erasing.containsKey(id)) return;

    final before = _state.fills.fillOf(id);
    if (before == null) return;
    _erasing[id] = before;
  }
```

6. `_scheduleSave` 를 바꿔 스티커·브러시까지 넘긴다:

```dart
  void _scheduleSave() {
    final dohan = _dohan;
    final id = _artworkId;
    if (dohan == null || id == null) return;
    autosave.schedule(
      Artwork(
        id: id,
        dohanId: dohan.meta.id,
        fills: _state.fills.toJson(),
        updatedAt: DateTime.now().toUtc(),
      ),
      stickers: _state.stickers.stickers,
      brushRevision: _state.brush.revision,
      bakeBrush: _bakeBrush,
    );
  }

  /// 브러시 레이어를 PNG 로 굽는다. 자동 저장이 **실제로 쓸 때만** 부른다 —
  /// 실측 53ms 라 탭마다 하면 끊긴다.
  Future<Uint8List?> _bakeBrush() async {
    final dohan = _dohan;
    if (dohan == null || _state.brush.isEmpty) return null;

    final size = dohan.regions.width;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    BrushPainter.paint(
      canvas,
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      _state.brush,
      _mask,
    );
    final picture = rec.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    // ByteData 는 더 큰 버퍼의 조각일 수 있다. .buffer 를 그대로 쓰면
    // offsetInBytes 를 무시해 엉뚱한 자리에서 읽는다 — 계획 2 에서 에셋 로딩에
    // 같은 실수를 했다가 리뷰가 잡았다.
    return Uint8List.sublistView(data);
  }
```

7. `dispose()` 에서 마스크를 해제한다. `unawaited(...)` 줄 앞에:

```dart
    _mask?.dispose();
    _mask = null;
```

- [ ] **Step 4: 전체 테스트와 분석 확인**

```bash
cd app && flutter test
cd app && flutter analyze
```

Expected: 전부 통과, `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 브러시 획과 지우개, 브러시 굽기 배선"
```

---

### Task 13: 컨트롤러 — 스티커 붙이고 옮기기

**Files:**
- Modify: `app/lib/coloring/coloring_controller.dart`
- Test: `app/test/coloring_controller_test.dart` (추가)

**Interfaces:**
- Consumes: `Sticker`·`StickerState`·`kStickerIds` (Task 4·8)
- Produces:
  - `void addSticker(String stickerId)` — 캔버스 한가운데에 기본 크기로
  - `Sticker? stickerAt(Offset canvasPoint)`
  - `void beginStickerDrag(Offset canvasPoint)`
  - `void updateStickerDrag({required double x, required double y, double? scale})`
  - `void endStickerDrag()`

**끌기를 명령 하나로 만든다.** 손가락이 움직이는 동안 스티커는 바로바로 따라가지만
되돌리기 스택에는 아무것도 쌓지 않는다. 손을 뗄 때 "출발 상태 → 도착 상태" 하나만 쌓는다 —
아이에게 되돌릴 단계는 "옮긴 일" 하나지 중간 프레임 수백 개가 아니다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/coloring_controller_test.dart` 에 추가한다:

```dart
  test('스티커를 붙이면 캔버스 한가운데에 놓인다', () {
    c.selectTool(ToolKind.sticker);
    c.addSticker('star-01');

    final list = c.state.stickers.stickers;
    expect(list, hasLength(1));
    expect(list.first.stickerId, 'star-01');
    expect(list.first.x, 2, reason: '가짜 도안이 4 폭이므로 한가운데는 2');
  });

  test('붙인 스티커를 되돌리면 사라진다', () {
    c.addSticker('star-01');
    expect(c.undo(), isTrue);
    expect(c.state.stickers.stickers, isEmpty);
  });

  test('같은 그림을 여러 번 붙일 수 있다', () {
    c.addSticker('star-01');
    c.addSticker('star-01');
    final list = c.state.stickers.stickers;
    expect(list, hasLength(2));
    expect(list.first.instanceId, isNot(list.last.instanceId));
  });

  test('스티커를 끌어 옮긴 뒤 되돌리면 제자리로 간다', () {
    c.addSticker('star-01');
    final start = c.state.stickers.stickers.first;

    c.beginStickerDrag(Offset(start.x, start.y));
    c.updateStickerDrag(x: 3, y: 1);
    c.endStickerDrag();

    expect(c.state.stickers.stickers.first.x, 3);

    expect(c.undo(), isTrue);
    expect(c.state.stickers.stickers.first.x, start.x);
    expect(c.state.stickers.stickers, hasLength(1), reason: '사라지면 안 된다');
  });

  test('끄는 동안에는 되돌리기 스택이 늘지 않는다', () {
    c.addSticker('star-01');
    final start = c.state.stickers.stickers.first;

    c.beginStickerDrag(Offset(start.x, start.y));
    c.updateStickerDrag(x: 1, y: 1);
    c.updateStickerDrag(x: 2, y: 2);
    c.updateStickerDrag(x: 3, y: 3);
    c.endStickerDrag();

    // 붙인 것 하나 + 옮긴 것 하나 = 되돌리기 두 번이면 아무것도 없어야 한다.
    expect(c.undo(), isTrue);
    expect(c.undo(), isTrue);
    expect(c.undo(), isFalse);
  });

  test('제자리에서 손을 떼면 아무 일도 없다', () {
    c.addSticker('star-01');
    final start = c.state.stickers.stickers.first;

    c.beginStickerDrag(Offset(start.x, start.y));
    c.endStickerDrag();

    expect(c.undo(), isTrue, reason: '붙인 것만 되돌아간다');
    expect(c.state.stickers.stickers, isEmpty);
  });

  test('빈 곳을 끌면 아무 일도 없다', () {
    c.addSticker('star-01');
    c.beginStickerDrag(const Offset(999, 999));
    c.updateStickerDrag(x: 0, y: 0);
    c.endStickerDrag();

    expect(c.state.stickers.stickers.first.x, 2, reason: '움직이지 않았다');
  });

  test('스티커를 지우개로 떼면 되돌리기로 제자리에 돌아온다', () {
    c.addSticker('star-01');
    c.addSticker('heart-01');

    c.selectTool(ToolKind.eraser);
    final first = c.state.stickers.stickers.first;
    c.beginStroke(Offset(first.x, first.y));
    c.endStroke();

    expect(c.state.stickers.stickers, hasLength(1));

    expect(c.undo(), isTrue);
    expect(c.state.stickers.stickers.map((s) => s.stickerId),
        ['star-01', 'heart-01'],
        reason: 'z 순서까지 복원해야 한다');
  });
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/coloring_controller_test.dart
```

Expected: FAIL — `addSticker` 가 없다

- [ ] **Step 3: 컨트롤러 수정**

1. import 추가:

```dart
import 'sticker_state.dart';
```

2. 필드 추가:

```dart
  /// 끌기 시작 시점의 스티커. 손을 뗄 때 이것과 비교해 명령 하나를 만든다.
  Sticker? _dragBefore;
```

3. `beginStroke` 의 **맨 앞**에 스티커 지우기를 넣는다 (지우개가 "맨 위 것"을 지우므로
스티커가 먼저다). `final kind = _strokeKind;` 줄 위에:

```dart
    if (_tool == ToolKind.eraser) {
      final hit = _state.stickers.topAt(canvasPoint);
      if (hit != null) {
        // 스티커를 떼려던 손짓이 밑의 그림까지 지우면 안 된다. 여기서 끝낸다.
        final index = _state.stickers.indexOf(hit.instanceId);
        _undo.push(
          StickerCommand(index: index, before: hit, after: null),
          _state,
        );
        _undosSinceChange = 0;
        _scheduleSave();
        notifyListeners();
        return;
      }
    }
```

4. 스티커 조작을 `dispose()` 앞에 추가한다:

```dart
  Sticker? stickerAt(Offset canvasPoint) =>
      _state.stickers.topAt(canvasPoint);

  /// 서랍에서 고른 스티커를 캔버스 한가운데에 놓는다.
  ///
  /// 놓는 동작이 실패할 수 없다는 것이 핵심이다 — 아이가 손을 어디서 떼든
  /// 스티커는 이미 화면에 있고, 마음에 안 들면 끌면 된다.
  void addSticker(String stickerId) {
    final dohan = _dohan;
    if (dohan == null) return;

    final centre = dohan.regions.width / 2;
    final sticker = Sticker(
      instanceId: '${DateTime.now().microsecondsSinceEpoch}',
      stickerId: stickerId,
      x: centre,
      y: centre,
    );

    _undo.push(
      StickerCommand(
        index: _state.stickers.stickers.length,
        before: null,
        after: sticker,
      ),
      _state,
    );
    _undosSinceChange = 0;
    _scheduleSave();
    notifyListeners();
  }

  void beginStickerDrag(Offset canvasPoint) {
    _dragBefore = _state.stickers.topAt(canvasPoint);
  }

  /// 손가락을 따라 바로 움직인다. 되돌리기 스택은 건드리지 않는다.
  void updateStickerDrag({
    required double x,
    required double y,
    double? scale,
  }) {
    final before = _dragBefore;
    if (before == null) return;
    final index = _state.stickers.indexOf(before.instanceId);
    if (index < 0) return;

    _state.stickers
        .replaceAt(index, before.copyWith(x: x, y: y, scale: scale));
    notifyListeners();
  }

  void endStickerDrag() {
    final before = _dragBefore;
    _dragBefore = null;
    if (before == null) return;

    final index = _state.stickers.indexOf(before.instanceId);
    if (index < 0) return;

    final after = _state.stickers.stickers[index];
    if (after.x == before.x &&
        after.y == before.y &&
        after.scale == before.scale) {
      return; // 제자리에서 손을 뗐다
    }

    // 스택에는 출발 → 도착 하나만 쌓는다. 중간 프레임 수백 개는 아이에게
    // 되돌릴 단계가 아니다. 명령이 제 손으로 적용하도록 먼저 되돌려 둔다.
    _state.stickers.replaceAt(index, before);
    _undo.push(
      StickerCommand(index: index, before: before, after: after),
      _state,
    );
    _undosSinceChange = 0;
    _scheduleSave();
    notifyListeners();
  }
```

- [ ] **Step 4: 전체 테스트와 분석 확인**

```bash
cd app && flutter test
cd app && flutter analyze
```

Expected: 전부 통과, `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app
git commit -m "feat(app): 스티커 붙이기와 끌어 옮기기"
```

---

### Task 14: 도구 줄 · 명도 버튼 · 스티커 서랍

**Files:**
- Create: `app/lib/ui/tool_bar.dart`
- Create: `app/lib/ui/shade_button.dart`
- Create: `app/lib/ui/sticker_drawer.dart`
- Test: `app/test/tool_widgets_test.dart`

**Interfaces:**
- Consumes: `ToolKind` (Task 11), `Shade` (Task 1), `kStickerIds` (Task 8)
- Produces:
  - `ToolBar({required ToolKind selected, required ValueChanged<ToolKind> onSelect})`
  - `ShadeButton({required Shade shade, required VoidCallback onCycle})`
  - `StickerDrawer({required ValueChanged<String> onPick})`
  - `const double kToolSize = 64;`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/tool_widgets_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/coloring/coloring_controller.dart' show ToolKind;
import 'package:kkumul/coloring/sticker_state.dart';
import 'package:kkumul/ui/palette_shades.dart';
import 'package:kkumul/ui/shade_button.dart';
import 'package:kkumul/ui/sticker_drawer.dart';
import 'package:kkumul/ui/tool_bar.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('도구가 다섯 개이고 전부 64dp 이상이다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      ToolBar(selected: ToolKind.bucket, onSelect: (_) {}),
    ));

    final tools = find.byType(ToolButton);
    expect(tools, findsNWidgets(5));

    for (final e in tools.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.right, lessThanOrEqualTo(320),
          reason: '다섯 개가 320dp 한 줄에 정확히 들어가야 한다');
    }
  });

  testWidgets('도구를 누르면 알려준다', (tester) async {
    ToolKind? picked;
    await tester.pumpWidget(_host(
      ToolBar(selected: ToolKind.bucket, onSelect: (t) => picked = t),
    ));

    await tester.tap(find.byType(ToolButton).at(3));
    expect(picked, ToolKind.eraser, reason: '네 번째가 지우개다');
  });

  testWidgets('고른 도구만 선택 표시가 켜진다', (tester) async {
    await tester.pumpWidget(_host(
      ToolBar(selected: ToolKind.brush, onSelect: (_) {}),
    ));

    final tools = find.byType(ToolButton);
    for (var i = 0; i < 5; i++) {
      expect(tester.widget<ToolButton>(tools.at(i)).selected, i == 2,
          reason: '$i 번째');
    }
  });

  testWidgets('명도 버튼이 64dp 이고 누르면 알려준다', (tester) async {
    var cycled = 0;
    await tester.pumpWidget(_host(
      ShadeButton(shade: Shade.base, onCycle: () => cycled++),
    ));

    final size = tester.getSize(find.byType(ShadeButton));
    expect(size.width, greaterThanOrEqualTo(64));
    expect(size.height, greaterThanOrEqualTo(64));

    await tester.tap(find.byType(ShadeButton));
    expect(cycled, 1);
  });

  testWidgets('스티커 서랍이 열 개를 보여주고 64dp 를 지킨다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(StickerDrawer(onPick: (_) {})));
    await tester.pumpAndSettle();

    final items = find.byType(StickerButton);
    expect(items, findsNWidgets(kStickerIds.length));

    for (final e in items.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.right, lessThanOrEqualTo(320));
    }
  });

  testWidgets('스티커를 누르면 id 를 알려준다', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(StickerDrawer(onPick: (id) => picked = id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(StickerButton).first);
    expect(picked, kStickerIds.first);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/tool_widgets_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:kkumul/ui/tool_bar.dart'`

- [ ] **Step 3: `tool_bar.dart` 작성**

```dart
import 'package:flutter/material.dart';

import '../coloring/coloring_controller.dart' show ToolKind;

/// 도구 칸 하나의 크기. 스펙 10.3 의 최소 터치 타겟이다.
const double kToolSize = 64;

/// 도구 하나를 고르는 칸.
class ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: kToolSize,
          height: kToolSize,
          child: Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFE6EFE9) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF246B4B)
                      : const Color(0xFFD8DCD8),
                  width: 3,
                ),
              ),
              child: Icon(icon,
                  size: 28,
                  color: selected
                      ? const Color(0xFF246B4B)
                      : const Color(0xFF6B736C)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 도구 다섯 개. 320dp 화면에서 64dp 다섯 개가 한 줄에 정확히 들어간다.
class ToolBar extends StatelessWidget {
  final ToolKind selected;
  final ValueChanged<ToolKind> onSelect;

  const ToolBar({super.key, required this.selected, required this.onSelect});

  static const _tools = <(ToolKind, IconData, String)>[
    (ToolKind.bucket, Icons.format_color_fill, '색 채우기'),
    (ToolKind.crayon, Icons.edit, '크레용'),
    (ToolKind.brush, Icons.brush, '붓'),
    (ToolKind.eraser, Icons.cleaning_services, '지우개'),
    (ToolKind.sticker, Icons.auto_awesome, '스티커'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kToolSize,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (kind, icon, label) in _tools)
            ToolButton(
              icon: icon,
              label: label,
              selected: kind == selected,
              onTap: () => onSelect(kind),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: `shade_button.dart` 작성**

```dart
import 'package:flutter/material.dart';

import 'palette_shades.dart';
import 'tool_bar.dart' show kToolSize;

/// 팔레트 명도를 한 바퀴 돌리는 버튼.
///
/// 앱바에 둔다. 24색을 다 펼치면 320dp 화면에서 팔레트가 본문의 59% 를 먹는다 —
/// 설계 문서 3.2절. 대신 여덟 색은 그대로 두고 이 버튼이 명도를 바꾼다.
class ShadeButton extends StatelessWidget {
  final Shade shade;
  final VoidCallback onCycle;

  const ShadeButton({super.key, required this.shade, required this.onCycle});

  static const _labels = {
    Shade.light: '연하게',
    Shade.base: '기본',
    Shade.dark: '진하게',
  };

  @override
  Widget build(BuildContext context) {
    // 지금 명도의 분홍을 보여 준다. 무엇이 바뀌는지를 글자 대신 색으로 알린다.
    final swatch = paletteShades[shade]!.first;
    return Semantics(
      label: '색 진하기 — ${_labels[shade]}',
      button: true,
      child: GestureDetector(
        onTap: onCycle,
        child: SizedBox(
          width: kToolSize,
          height: kToolSize,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF757D75), width: 3),
              ),
              child: Icon(
                switch (shade) {
                  Shade.light => Icons.brightness_low,
                  Shade.base => Icons.brightness_medium,
                  Shade.dark => Icons.brightness_high,
                },
                size: 18,
                color: const Color(0xFF202923),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: `sticker_drawer.dart` 작성**

```dart
import 'package:flutter/material.dart';

import '../coloring/sticker_state.dart';
import 'tool_bar.dart' show kToolSize;

/// 스티커 하나를 고르는 칸.
class StickerButton extends StatelessWidget {
  final String stickerId;
  final VoidCallback onTap;

  const StickerButton({
    super.key,
    required this.stickerId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '스티커 $stickerId',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: kToolSize,
          height: kToolSize,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset('assets/stickers/$stickerId.png'),
          ),
        ),
      ),
    );
  }
}

/// 스티커 서랍.
///
/// 열 개뿐인 것은 화면 때문이다 — 320dp 에서 64dp 칸이 한 줄에 다섯이고
/// 상황별 영역이 두 줄이다. 스크롤되는 줄은 글을 못 읽는 아이에게 보이지
/// 않는 것과 같다.
class StickerDrawer extends StatelessWidget {
  final ValueChanged<String> onPick;

  const StickerDrawer({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final id in kStickerIds)
          StickerButton(stickerId: id, onTap: () => onPick(id)),
      ],
    );
  }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd app && flutter test test/tool_widgets_test.dart
cd app && flutter analyze
```

Expected: PASS — 6개 테스트 통과, `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add app
git commit -m "feat(app): 도구 줄, 명도 버튼, 스티커 서랍"
```

---

### Task 15: 화면 통합

**Files:**
- Modify: `app/lib/coloring/coloring_painter.dart` (브러시·스티커 레이어 추가)
- Modify: `app/lib/ui/coloring_screen.dart`
- Modify: `app/lib/main.dart` (설정 읽기)
- Test: `app/test/coloring_screen_test.dart` (기존 5개는 그대로 두고 추가)

**Interfaces:**
- Consumes: 앞선 전부
- Produces: 없음 (계획의 끝)

**세로 예산 (320 × 640)**: 앱바 64 + 캔버스 350 + 도구 줄 64 + 상황별 영역 128 + 제스처 34.
상황별 영역의 **높이는 고정**이다 — 도구를 바꿀 때 높이가 변하면 캔버스가 늘었다 줄었다
하면서 아이가 그리던 그림이 화면에서 튄다.

- [ ] **Step 1: `ColoringPainter` 에 레이어 추가**

`app/lib/coloring/coloring_painter.dart` 의 `ColoringPainter` 에 필드 넷을 추가하고,
`paint` 에서 채움과 선화 **사이**에 브러시를, 선화 **뒤**에 스티커를 그린다.
합성 순서가 한 곳에 모여 있어야 Global Constraints 를 지켰는지 눈으로 확인할 수 있다.

생성자에 추가할 필드:

```dart
  final BrushState? brush;
  final ui.Image? paintableMask;
  final List<Sticker> stickers;
  final Map<String, ui.Image> stickerImages;
```

기본값은 `brush: null`, `paintableMask: null`, `stickers: const []`,
`stickerImages: const {}` 로 두어 기존 호출부(`fill_shader_test.dart`)가 그대로 돈다.

`paint` 에서 선화를 그리는 줄 **앞에**:

```dart
    // 3. 브러시 — 선화 아래다. 선이 항상 살아 있어야 한다.
    final b = brush;
    if (b != null) {
      BrushPainter.paint(
        canvas,
        ui.Rect.fromLTWH(0, 0, canvasSize.toDouble(), canvasSize.toDouble()),
        b,
        paintableMask,
      );
    }
```

선화를 그리는 줄 **뒤에**:

```dart
    // 5. 스티커 — 선화 위다. 스티커가 선에 가리면 안 된다(상위 스펙 7.1).
    for (final s in stickers) {
      final img = stickerImages[s.stickerId];
      if (img == null) continue;
      canvas.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        s.bounds,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    }
```

`shouldRepaint` 에 아래를 `||` 로 덧붙인다:

```dart
      old.brush != brush ||
      old.paintableMask != paintableMask ||
      old.stickers.length != stickers.length ||
      old.stickerImages.length != stickerImages.length
```

브러시는 같은 객체를 계속 쓰므로 `!=` 로는 안 잡힌다. 화면이 `setState` 로 다시 그리므로
문제가 없지만, 확실히 하려면 `BrushState.revision` 을 함께 보내도 된다 —
`final int brushRevision;` 를 추가하고 `old.brushRevision != brushRevision` 을 넣는 것이
가장 단순하다. **그렇게 할 것.**

- [ ] **Step 2: 실패하는 테스트 작성**

`app/test/coloring_screen_test.dart` 에 추가한다. 상단 import 에
`import 'package:kkumul/settings/settings.dart';`,
`import 'package:kkumul/ui/shade_button.dart';`,
`import 'package:kkumul/ui/sticker_drawer.dart';`,
`import 'package:kkumul/ui/tool_bar.dart';` 를 추가한다.
(`ColorSwatchButton` 은 이미 있는 `palette_bar.dart` import 로 들어온다.)

```dart
  testWidgets('아동 모드는 도구 다섯 개와 명도 버튼을 보여준다', (tester) async {
    controller.ageMode = AgeMode.child;
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ToolButton), findsNWidgets(5));
    expect(find.byType(ShadeButton), findsOneWidget);
  });

  testWidgets('유아 모드는 도구 줄과 명도 버튼을 숨긴다', (tester) async {
    controller.ageMode = AgeMode.toddler;
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ToolButton), findsNothing,
        reason: '유아는 양동이 하나뿐이다 — 상위 스펙 9장');
    expect(find.byType(ShadeButton), findsNothing);
  });

  testWidgets('명도 버튼을 누르면 팔레트 색이 바뀐다', (tester) async {
    controller.ageMode = AgeMode.child;
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final before = controller.selectedColor;
    await tester.tap(find.byType(ShadeButton));
    await tester.pump();

    expect(controller.selectedColor, isNot(before));
    expect(controller.colorIndex, 0, reason: '고른 자리는 그대로다');
  });

  testWidgets('스티커 도구를 고르면 서랍이 나온다', (tester) async {
    controller.ageMode = AgeMode.child;
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(StickerButton), findsNothing);

    await tester.tap(find.byType(ToolButton).at(4));
    await tester.pumpAndSettle();

    expect(find.byType(StickerButton), findsWidgets);
    expect(find.byType(ColorSwatchButton), findsNothing,
        reason: '스티커를 고를 때는 팔레트가 필요 없다');
  });

  testWidgets('도구를 바꿔도 캔버스 크기가 변하지 않는다', (tester) async {
    // 높이가 변하면 아이가 그리던 그림이 화면에서 튄다.
    controller.ageMode = AgeMode.child;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byKey(const ValueKey('coloring-canvas')));

    await tester.tap(find.byType(ToolButton).at(4)); // 스티커
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('coloring-canvas'))), before);

    await tester.tap(find.byType(ToolButton).at(3)); // 지우개
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('coloring-canvas'))), before);
  });

  testWidgets('좁은 화면에서 도구 줄도 64dp 를 지키고 화면 안에 있다',
      (tester) async {
    controller.ageMode = AgeMode.child;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    for (final e in find.byType(ToolButton).evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.width, greaterThanOrEqualTo(64));
      expect(r.height, greaterThanOrEqualTo(64));
      expect(r.right, lessThanOrEqualTo(320));
      expect(r.bottom, lessThanOrEqualTo(640 - 34),
          reason: '제스처 영역에 걸치면 도구 대신 홈 제스처가 먹는다');
    }
  });

  testWidgets('크레용으로 끌면 획이 생긴다', (tester) async {
    controller.ageMode = AgeMode.child;
    await tester.pumpWidget(MaterialApp(
      home: ColoringScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ToolButton).at(1)); // 크레용
    await tester.pump();

    final box = tester.getRect(find.byKey(const ValueKey('coloring-canvas')));
    await tester.drag(
      find.byKey(const ValueKey('coloring-canvas')),
      const Offset(40, 0),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(controller.state.brush.strokes, hasLength(1));
    expect(box.width, greaterThan(0));
  });
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd app && flutter test test/coloring_screen_test.dart
```

Expected: FAIL — `ToolButton` 이 화면에 없다

- [ ] **Step 4: 화면 수정**

`app/lib/ui/coloring_screen.dart`:

1. import 추가:

```dart
import '../coloring/sticker_state.dart';
import '../settings/settings.dart';
import 'palette_shades.dart';
import 'shade_button.dart';
import 'sticker_drawer.dart';
import 'tool_bar.dart';
```

2. 상태에 스티커 그림 캐시를 추가한다:

```dart
  final Map<String, ui.Image> _stickerImages = {};
```

3. `_prepare()` 끝의 `setState` 앞에 스티커 그림을 읽는다:

```dart
    final loadedStickers = <String, ui.Image>{};
    for (final id in kStickerIds) {
      final data = await rootBundle.load('assets/stickers/$id.png');
      loadedStickers[id] = await _decodeBytes(Uint8List.sublistView(data));
    }
```

그리고 `setState` 안에 `_stickerImages..clear()..addAll(loadedStickers);` 를 넣는다.
`rootBundle` 을 쓰려면 `import 'package:flutter/services.dart' show rootBundle;` 가 필요하다.
`_decodeBytes` 는 계획 2 의 `_decode` 와 같은 함수다 — 이름이 다르면 있는 것을 쓸 것.

4. `dispose()` 에서 스티커 그림도 해제한다:

```dart
    for (final img in _stickerImages.values) {
      img.dispose();
    }
    _stickerImages.clear();
```

5. `build` 의 `appBar` `actions` 에 명도 버튼을 되돌리기 앞에 넣는다:

```dart
        actions: [
          if (c.ageMode == AgeMode.child)
            ShadeButton(shade: c.shade, onCycle: c.cycleShade),
          IconButton(
            // ... 기존 되돌리기 버튼 그대로
```

6. `body` 의 `Column` children 을 아래로 바꾼다:

```dart
          Expanded(
            child: c.dohan == null
                ? const Center(child: CircularProgressIndicator())
                : _buildCanvas(c),
          ),
          if (c.ageMode == AgeMode.child)
            ToolBar(selected: c.tool, onSelect: c.selectTool),
          // 상황별 영역의 높이는 고정이다. 도구를 바꿀 때 높이가 변하면
          // 캔버스가 늘었다 줄었다 하면서 아이가 그리던 그림이 화면에서 튄다.
          SizedBox(height: 128, child: Center(child: _buildContext(c))),
```

7. `_buildContext` 를 추가한다:

```dart
  Widget _buildContext(ColoringController c) {
    switch (c.tool) {
      case ToolKind.sticker:
        return StickerDrawer(onPick: c.addSticker);
      case ToolKind.eraser:
        return const SizedBox.shrink();
      case ToolKind.bucket:
      case ToolKind.crayon:
      case ToolKind.brush:
        return PaletteBar(
          shade: c.shade,
          selectedIndex: c.colorIndex,
          onPickIndex: c.pickColorIndex,
        );
    }
  }
```

`_paletteIndex` 필드와 그것을 쓰던 `setState` 는 지운다 — 이제 컨트롤러가 들고 있다.

8. `_buildCanvas` 의 `GestureDetector` 를 바꾼다:

```dart
        return GestureDetector(
          key: const ValueKey('coloring-canvas'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => c.tapAt(transform.toCanvas(d.localPosition)),
          onPanStart: (d) {
            final p = transform.toCanvas(d.localPosition);
            if (c.tool == ToolKind.sticker) {
              c.beginStickerDrag(p);
            } else {
              c.beginStroke(p);
            }
          },
          onPanUpdate: (d) {
            final p = transform.toCanvas(d.localPosition);
            if (c.tool == ToolKind.sticker) {
              c.updateStickerDrag(x: p.dx, y: p.dy);
            } else {
              c.extendStroke(p);
            }
          },
          onPanEnd: (_) {
            if (c.tool == ToolKind.sticker) {
              c.endStickerDrag();
            } else {
              c.endStroke();
            }
          },
```

`onTapDown` 과 `onPanStart` 를 한 `GestureDetector` 에 같이 두는 것은 의도된 것이다.
끌기를 시작해도 `onTapDown` 이 먼저 한 번 불리는데, `tapAt` 은 양동이가 아니면 바로
`false` 로 빠지므로(태스크 11) 크레용으로 그을 때 엉뚱한 칠이 생기지 않는다.

9. `_FittedColoringPainter` 에 넘기는 `ColoringPainter` 에 새 인자를 준다:

```dart
                    inner: ColoringPainter(
                      shader: _shader!,
                      regions: _regionsImage!,
                      palette: _paletteImage!,
                      lineart: _lineartImage!,
                      canvasSize: canvasSize,
                      brush: c.state.brush,
                      brushRevision: c.state.brush.revision,
                      paintableMask: c.paintableMask,
                      stickers: c.state.stickers.stickers,
                      stickerImages: _stickerImages,
                    ),
```

- [ ] **Step 5: `main.dart` 에서 설정 읽기**

`runApp` 앞, 컨트롤러 생성 부분을 바꾼다:

```dart
  final settings = await SettingsStore(docs).load();
  final controller = ColoringController(
    source: BundledDohanSource(),
    autosave: Autosave(repository: repository),
    ageMode: settings.ageMode,
  );
```

`SettingsStore.load()` 도 읽기 실패 시 던지므로, 이미 있는 `try` 블록 **안으로** 넣거나
따로 감싼다. 감싸지 않으면 계획 2 에서 고친 "파일 하나 때문에 앱이 영영 안 뜨는" 문제가
설정 파일로 되살아난다. `import '../settings/settings.dart';` 가 아니라
`import 'settings/settings.dart';` 다.

- [ ] **Step 6: 전체 테스트와 분석 확인**

```bash
cd app && flutter test
cd app && flutter analyze
```

Expected: 전부 통과, `No issues found!`

- [ ] **Step 7: 커밋**

```bash
git add app
git commit -m "feat(app): 도구 줄과 상황별 영역을 붙이고 브러시·스티커를 합성한다"
```

---

## 실행 중 기억할 것

- **계획서 코드를 의심할 것.** 계획 1·2 를 합쳐 열일곱 건이 계획서가 제공한 코드 자체의
  버그였고, 구현자의 전사는 매번 정확했다. 테스트가 기대와 다르면 **테스트를 고치지 말고**
  멈추고 보고할 것. 계획이 틀렸을 가능성이 훨씬 높다.
- **숫자는 방금 돌린 출력에서 그대로 인용할 것.** 계획서에 적힌 기대 개수가 틀렸을 수도 있다.
- **`flutter analyze` 를 `No issues found!` 로 유지할 것.** 계획 2 에서 계획서가 준 `const`
  하나 때문에 두 번 깨졌다.
- **`flutter test` 를 `grep` 에 파이프하지 말 것.** 블록 버퍼링 때문에 멈춘 것과 끝난 것이
  구분되지 않는다.
- 브러시 굵기·스티커 크기(설계 문서 7.4절)는 **추정치**다. 실제로 그어 보고 어색하면
  계획서가 아니라 그 표를 고칠 것.
