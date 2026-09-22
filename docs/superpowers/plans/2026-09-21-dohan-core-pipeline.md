# dohan_core 및 에셋 파이프라인 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 선화 이미지를 입력받아 "칠할 수 있는 영역이 분리된 도안 패키지"를 산출하는 순수 Dart 라이브러리와 배치 생성 CLI를 만든다.

**Architecture:** `packages/dohan_core/`는 Flutter에 의존하지 않는 순수 Dart 패키지다. 이진화 → 선 끊김 보정 → 연결요소 라벨링 → 영역 정리 → 인덱스맵 인코딩의 단계를 각각 독립 파일로 구현하고 `pipeline.dart`가 조립한다. 이 패키지는 나중에 Flutter 앱(온디바이스 사진 변환)과 CLI(내장 도안 배치 생성) 양쪽이 공유한다 — 알고리즘을 두 번 구현하지 않는 것이 이 설계의 핵심이다.

**Tech Stack:** Dart 3.x · `package:image` ^4.2.0 · `package:args` ^2.5.0 · `package:test` ^1.25.0 · Python 3.14 (프롬프트 도구)

**Spec:** [docs/superpowers/specs/2026-09-21-kkumul-coloring-app-design.md](../specs/2026-09-21-kkumul-coloring-app-design.md)

## Global Constraints

스펙에서 그대로 옮긴 값들이다. 모든 태스크의 요구사항에 암묵적으로 포함된다.

- 영역 ID `0` = 선 픽셀 (칠할 수 없고 브러시도 얹히지 않는다)
- 영역 ID `1` = `BACKGROUND` (도안 바깥, 칠할 수 없다)
- 영역 ID `2` 이상 = 칠할 수 있는 영역
- 인덱스맵 최대 영역 수: 65,535
- 인덱스맵 인코딩: R = ID 하위 8bit, G = ID 상위 8bit, B = 0, A = 255
- 인덱스맵 해상도: 1024 × 1024 고정. 리샘플링·손실 압축·팔레트 양자화 금지
- 선화 해상도: 1024, 고밀도용 `lineart@2x.png`는 2048
- 품질 게이트: 영역 수 < 4 리젝트 · 영역 수 > 120 리젝트 · `BACKGROUND` 면적 < 캔버스의 60% 리젝트
- 도안 패키지 구성: `lineart.png` + `regions.png` + `meta.json`
- 사용자 대면 문자열은 한국어
- `packages/dohan_core/`는 `flutter` 및 `dart:ui`에 의존하지 않는다 — `dart test`로 단독 실행되어야 한다

## 스펙에서 수정이 필요한 값 하나

스펙 6.2절의 "최소 영역 내접원 지름 < 64dp"는 **그대로 쓸 수 없다.** 64dp는 UI 버튼의 최소 터치 타겟 기준이고, 1024px 캔버스가 폰에서 약 340dp로 표시되면 64dp ≈ 193 캔버스 픽셀이다. 이 기준을 적용하면 공룡 발톱, 자동차 헤드라이트 같은 정상적인 디테일이 전부 병합되어 도안이 뭉개진다.

이 계획은 **24dp ≈ 72 캔버스 픽셀**을 기본값(`minTapDiameterPx: 72`)으로 쓰고, 카테고리별로 조정 가능한 파라미터로 노출한다. UI 컨트롤의 64dp 최소 터치 타겟 규칙(스펙 10.3)은 그대로 유지된다 — 둘은 다른 기준이다.

계획 1 완료 후 실제 도안으로 이 값을 재측정하고 스펙 6.2절을 갱신한다.

## File Structure

```
packages/dohan_core/
  pubspec.yaml
  lib/
    dohan_core.dart              공개 API 배럴
    src/
      types.dart                 RegionMap, BinaryMask, ID 상수, ID 인코딩
      binarize.dart              그레이스케일 + 적응형 이진화
      morphology.dart            선 두께 추정, 팽창/침식, 닫기 연산
      label_regions.dart         연결요소 라벨링 (union-find)
      cleanup.dart               배경 지정, 파편 병합, ID 재부여
      quality_gate.dart          품질 게이트와 판정 리포트
      index_map.dart             인덱스맵 PNG 인코딩/디코딩
      dohan_package.dart         DohanMeta, 패키지 읽기/쓰기
      preview.dart               검수용 영역 색칠 미리보기
      pipeline.dart              단계 조립
  test/
    support/fixtures.dart        문자열 격자로 마스크 만드는 테스트 헬퍼
    types_test.dart
    binarize_test.dart
    morphology_test.dart
    label_regions_test.dart
    cleanup_test.dart
    quality_gate_test.dart
    index_map_test.dart
    dohan_package_test.dart
    preview_test.dart
    pipeline_test.dart           누수 회귀 테스트 포함

tools/dohan_cli/
  pubspec.yaml
  bin/dohan.dart                 build / preview 서브커맨드

tools/dohan_gen/
  prompts.py                     카테고리별 프롬프트 템플릿
  providers.py                   이미지 수급 provider 인터페이스 + 파일시스템 구현
  generate.py                    CLI 진입점
  README.md
```

각 파일이 한 가지 책임만 진다. `types.dart`를 제외한 모든 파일은 서로를 직접 참조하지 않고 `types.dart`의 자료형으로만 소통한다 — 단계를 독립적으로 테스트하고 교체할 수 있게 하기 위해서다.

---

### Task 1: 개발 환경과 `dohan_core` 패키지 골격

**Files:**
- Create: `packages/dohan_core/pubspec.yaml`
- Create: `packages/dohan_core/lib/dohan_core.dart`
- Create: `packages/dohan_core/lib/src/types.dart`
- Create: `packages/dohan_core/analysis_options.yaml`
- Test: `packages/dohan_core/test/types_test.dart`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: `kRegionLine`, `kRegionBackground`, `kRegionFirstFillable`, `kMaxRegionId` 상수 · `BinaryMask` · `RegionMap` · `encodeRegionId(int) -> List<int>` · `decodeRegionId(int r, int g) -> int`

- [ ] **Step 1: Flutter SDK 설치 확인**

이 PC에는 Flutter가 설치되어 있지 않다. 먼저 확인한다.

```bash
flutter --version
```

설치되어 있지 않으면 Chocolatey로 설치한다 (관리자 PowerShell):

```powershell
choco install flutter -y
```

Chocolatey를 쓰지 않으면 https://docs.flutter.dev/get-started/install/windows 에서 SDK zip을 받아 `C:\src\flutter`에 풀고 `C:\src\flutter\bin`을 PATH에 추가한다.

설치 후 확인:

```bash
flutter --version
dart --version
```

Expected: Dart 3.x 이상이 출력된다.

- [ ] **Step 2: 패키지 골격 생성**

```bash
mkdir -p packages/dohan_core/lib/src packages/dohan_core/test/support
```

`packages/dohan_core/pubspec.yaml`:

```yaml
name: dohan_core
description: 선화 이미지를 칠할 수 있는 영역이 분리된 도안으로 변환하는 순수 Dart 라이브러리.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.5.0

dependencies:
  image: ^4.2.0

dev_dependencies:
  test: ^1.25.0
  lints: ^4.0.0
```

`packages/dohan_core/analysis_options.yaml`:

```yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
```

- [ ] **Step 3: 실패하는 테스트 작성**

`packages/dohan_core/test/types_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

void main() {
  group('영역 ID 상수', () {
    test('선은 0, 배경은 1, 칠할 수 있는 영역은 2부터', () {
      expect(kRegionLine, 0);
      expect(kRegionBackground, 1);
      expect(kRegionFirstFillable, 2);
      expect(kMaxRegionId, 0xFFFF);
    });
  });

  group('인덱스맵 ID 인코딩', () {
    test('0부터 65535까지 왕복이 손실 없이 된다', () {
      for (final id in [0, 1, 2, 127, 255, 256, 257, 4096, 65534, 65535]) {
        final rgba = encodeRegionId(id);
        expect(rgba.length, 4, reason: 'RGBA 4바이트여야 한다');
        expect(rgba[2], 0, reason: 'B 채널은 예약되어 0이다');
        expect(rgba[3], 255, reason: 'A 채널은 항상 불투명하다');
        expect(decodeRegionId(rgba[0], rgba[1]), id,
            reason: 'ID $id 왕복 실패');
      }
    });

    test('R은 하위 8bit, G는 상위 8bit', () {
      expect(encodeRegionId(0x1234), [0x34, 0x12, 0, 255]);
    });
  });

  group('RegionMap', () {
    test('좌표 접근과 영역 개수 집계', () {
      final map = RegionMap.filled(4, 3, kRegionBackground);
      map.set(1, 1, 5);
      map.set(2, 1, 5);
      map.set(3, 2, 7);

      expect(map.at(1, 1), 5);
      expect(map.at(0, 0), kRegionBackground);
      expect(map.fillableRegionIds, {5, 7});
      expect(map.fillableRegionCount, 2);
      expect(map.areaByRegion()[5], 2);
      expect(map.areaByRegion()[kRegionBackground], 9);
    });
  });

  group('BinaryMask', () {
    test('선 픽셀 설정과 집계', () {
      final mask = BinaryMask.blank(3, 2);
      expect(mask.inkCount, 0);
      mask.setInk(1, 0, true);
      mask.setInk(2, 1, true);
      expect(mask.isInk(1, 0), isTrue);
      expect(mask.isInk(0, 0), isFalse);
      expect(mask.inkCount, 2);
    });
  });
}
```

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart pub get && dart test test/types_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:dohan_core/dohan_core.dart'`

- [ ] **Step 5: 최소 구현**

`packages/dohan_core/lib/src/types.dart`:

```dart
import 'dart:typed_data';

/// 선 픽셀. 칠할 수 없고 브러시도 얹히지 않는다.
const int kRegionLine = 0;

/// 도안 바깥 배경. 칠할 수 없다.
const int kRegionBackground = 1;

/// 칠할 수 있는 영역에 부여되는 첫 ID.
const int kRegionFirstFillable = 2;

/// 인덱스맵이 표현할 수 있는 최대 영역 ID.
const int kMaxRegionId = 0xFFFF;

/// 선과 여백 두 값만 갖는 이진 마스크. 값 1이 선이다.
class BinaryMask {
  final int width;
  final int height;
  final Uint8List ink;

  BinaryMask(this.width, this.height, this.ink)
      : assert(ink.length == width * height);

  factory BinaryMask.blank(int width, int height) =>
      BinaryMask(width, height, Uint8List(width * height));

  bool isInk(int x, int y) => ink[y * width + x] == 1;

  void setInk(int x, int y, bool value) {
    ink[y * width + x] = value ? 1 : 0;
  }

  int get inkCount {
    var n = 0;
    for (final v in ink) {
      if (v == 1) n++;
    }
    return n;
  }
}

/// 픽셀마다 영역 ID를 담는 격자.
class RegionMap {
  final int width;
  final int height;
  final Uint16List ids;

  RegionMap(this.width, this.height, this.ids)
      : assert(ids.length == width * height);

  factory RegionMap.filled(int width, int height, int id) => RegionMap(
        width,
        height,
        Uint16List(width * height)..fillRange(0, width * height, id),
      );

  int at(int x, int y) => ids[y * width + x];

  void set(int x, int y, int id) {
    ids[y * width + x] = id;
  }

  /// 칠할 수 있는 영역(ID 2 이상)의 ID 집합.
  Set<int> get fillableRegionIds {
    final seen = <int>{};
    for (final id in ids) {
      if (id >= kRegionFirstFillable) seen.add(id);
    }
    return seen;
  }

  int get fillableRegionCount => fillableRegionIds.length;

  /// 영역 ID별 픽셀 수. 선(0)과 배경(1)도 포함한다.
  Map<int, int> areaByRegion() {
    final areas = <int, int>{};
    for (final id in ids) {
      areas[id] = (areas[id] ?? 0) + 1;
    }
    return areas;
  }
}

/// 영역 ID를 RGBA 4바이트로 인코딩한다.
/// R = 하위 8bit, G = 상위 8bit, B = 0(예약), A = 255.
List<int> encodeRegionId(int id) {
  assert(id >= 0 && id <= kMaxRegionId, '영역 ID 범위를 벗어났습니다: $id');
  return [id & 0xFF, (id >> 8) & 0xFF, 0, 255];
}

/// RGBA의 R/G 채널에서 영역 ID를 복원한다.
int decodeRegionId(int r, int g) => r | (g << 8);
```

`packages/dohan_core/lib/dohan_core.dart`:

```dart
/// 선화 이미지를 칠할 수 있는 영역이 분리된 도안으로 변환한다.
library dohan_core;

export 'src/types.dart';
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test test/types_test.dart
```

Expected: PASS — 5개 테스트 전부 통과

- [ ] **Step 7: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): 영역 ID 자료형과 인덱스맵 인코딩"
```

---

### Task 2: 적응형 이진화

**Files:**
- Create: `packages/dohan_core/lib/src/binarize.dart`
- Modify: `packages/dohan_core/lib/dohan_core.dart`
- Test: `packages/dohan_core/test/binarize_test.dart`

**Interfaces:**
- Consumes: `BinaryMask` (Task 1)
- Produces: `toGrayscale(img.Image) -> Uint8List` · `binarize(img.Image, {int window, int offset}) -> BinaryMask`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/dohan_core/test/binarize_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// 흰 배경에 검은 수직 막대가 있는 테스트 이미지.
img.Image _barImage({int size = 64, int barX = 30, int barWidth = 4}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
  for (var y = 0; y < size; y++) {
    for (var x = barX; x < barX + barWidth; x++) {
      im.setPixelRgba(x, y, 0, 0, 0, 255);
    }
  }
  return im;
}

void main() {
  group('toGrayscale', () {
    test('흰색은 255, 검은색은 0에 가깝다', () {
      final im = _barImage();
      final gray = toGrayscale(im);
      expect(gray.length, 64 * 64);
      expect(gray[0], greaterThan(250), reason: '좌상단은 흰 배경');
      expect(gray[0 * 64 + 31], lessThan(5), reason: '막대 내부는 검정');
    });
  });

  group('binarize', () {
    test('검은 막대는 선으로, 흰 배경은 여백으로 분류한다', () {
      final mask = binarize(_barImage());

      expect(mask.isInk(31, 10), isTrue, reason: '막대 중심은 선이어야 한다');
      expect(mask.isInk(0, 0), isFalse, reason: '멀리 떨어진 배경은 여백');
      expect(mask.isInk(63, 63), isFalse);
    });

    test('완전히 흰 이미지에는 선이 하나도 없다', () {
      final im = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));

      expect(binarize(im).inkCount, 0);
    });

    test('조명이 기울어도 선을 놓치지 않는다', () {
      // 왼쪽은 밝고 오른쪽으로 갈수록 어두워지는 배경 위의 검은 막대.
      final im = img.Image(width: 64, height: 64, numChannels: 4);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final v = 255 - x * 2; // 255 → 129
          im.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      for (var y = 0; y < 64; y++) {
        for (var x = 50; x < 54; x++) {
          im.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }

      final mask = binarize(im);
      expect(mask.isInk(51, 32), isTrue,
          reason: '어두운 영역에 있어도 막대는 지역 평균보다 훨씬 어둡다');
      expect(mask.isInk(20, 32), isFalse,
          reason: '기울어진 배경 자체는 선이 아니다');
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart test test/binarize_test.dart
```

Expected: FAIL — `Undefined name 'toGrayscale'`

- [ ] **Step 3: 최소 구현**

`packages/dohan_core/lib/src/binarize.dart`:

```dart
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'types.dart';

/// 이미지를 8bit 그레이스케일 격자로 변환한다.
Uint8List toGrayscale(img.Image src) {
  final out = Uint8List(src.width * src.height);
  var i = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      out[i++] = img.getLuminance(src.getPixel(x, y)).round().clamp(0, 255);
    }
  }
  return out;
}

/// 지역 평균 기반 적응형 이진화.
///
/// 픽셀 밝기가 주변 [window]×[window] 평균보다 [offset] 이상 어두우면 선으로
/// 본다. 전역 임계값과 달리 사진의 그림자나 기울어진 조명에서도 선을 잃지
/// 않는다. 적분 영상을 써서 창 크기와 무관하게 O(픽셀 수)로 동작한다.
BinaryMask binarize(img.Image src, {int window = 31, int offset = 10}) {
  final w = src.width;
  final h = src.height;
  final gray = toGrayscale(src);

  // 적분 영상: (w+1) × (h+1), integral[y+1][x+1] = 좌상단 직사각형의 합
  final integral = Int64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    for (var x = 0; x < w; x++) {
      rowSum += gray[y * w + x];
      integral[(y + 1) * (w + 1) + (x + 1)] =
          integral[y * (w + 1) + (x + 1)] + rowSum;
    }
  }

  int rectSum(int x0, int y0, int x1, int y1) => (integral[(y1 + 1) * (w + 1) + (x1 + 1)] -
          integral[y0 * (w + 1) + (x1 + 1)] -
          integral[(y1 + 1) * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0])
      .toInt();

  final r = window ~/ 2;
  final mask = BinaryMask.blank(w, h);
  for (var y = 0; y < h; y++) {
    final y0 = y - r < 0 ? 0 : y - r;
    final y1 = y + r >= h ? h - 1 : y + r;
    for (var x = 0; x < w; x++) {
      final x0 = x - r < 0 ? 0 : x - r;
      final x1 = x + r >= w ? w - 1 : x + r;
      final count = (x1 - x0 + 1) * (y1 - y0 + 1);
      final mean = rectSum(x0, y0, x1, y1) / count;
      mask.ink[y * w + x] = gray[y * w + x] < mean - offset ? 1 : 0;
    }
  }
  return mask;
}
```

`packages/dohan_core/lib/dohan_core.dart`에 추가:

```dart
export 'src/binarize.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test test/binarize_test.dart
```

Expected: PASS — 4개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): 적분 영상 기반 적응형 이진화"
```

---

### Task 3: 선 두께 추정과 선 끊김 보정

이 태스크가 이 프로젝트에서 누수를 막는 핵심이다. AI가 생성한 선화와 아이가 종이에 그린 스케치는 거의 항상 선이 미세하게 끊겨 있고, 끊긴 선에 색을 부으면 도안 전체로 샌다.

**Files:**
- Create: `packages/dohan_core/lib/src/morphology.dart`
- Create: `packages/dohan_core/test/support/fixtures.dart`
- Modify: `packages/dohan_core/lib/dohan_core.dart`
- Test: `packages/dohan_core/test/morphology_test.dart`

**Interfaces:**
- Consumes: `BinaryMask` (Task 1)
- Produces: `estimateLineWidth(BinaryMask) -> int` · `dilate(BinaryMask, int radius) -> BinaryMask` · `erode(BinaryMask, int radius) -> BinaryMask` · `closeLines(BinaryMask, {int? radius}) -> BinaryMask` · 테스트 헬퍼 `maskFromRows(List<String>) -> BinaryMask`

- [ ] **Step 1: 테스트 헬퍼 작성**

`packages/dohan_core/test/support/fixtures.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';

/// 문자열 격자로 마스크를 만든다. '#'은 선, 그 밖의 문자는 여백이다.
///
/// 이 헬퍼 덕분에 테스트에서 도안 모양을 눈으로 읽을 수 있다.
BinaryMask maskFromRows(List<String> rows) {
  if (rows.isEmpty) {
    throw ArgumentError('행이 최소 하나는 있어야 합니다.');
  }
  final h = rows.length;
  final w = rows.first.length;
  for (final row in rows) {
    if (row.length != w) {
      throw ArgumentError('모든 행의 길이가 같아야 합니다: "$row"');
    }
  }
  final mask = BinaryMask.blank(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      mask.ink[y * w + x] = rows[y][x] == '#' ? 1 : 0;
    }
  }
  return mask;
}

/// 마스크를 문자열 격자로 되돌린다. 실패한 테스트를 눈으로 보기 위한 용도.
List<String> rowsFromMask(BinaryMask mask) => [
      for (var y = 0; y < mask.height; y++)
        String.fromCharCodes([
          for (var x = 0; x < mask.width; x++)
            mask.isInk(x, y) ? 0x23 /* # */ : 0x2E /* . */
        ])
    ];
```

- [ ] **Step 2: 실패하는 테스트 작성**

`packages/dohan_core/test/morphology_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('estimateLineWidth', () {
    test('3픽셀 두께 선에서 3을 얻는다', () {
      final mask = maskFromRows([
        '..........',
        '...###....',
        '...###....',
        '...###....',
        '..........',
      ]);

      expect(estimateLineWidth(mask), 3);
    });

    test('선이 없으면 1을 반환한다', () {
      expect(estimateLineWidth(maskFromRows(['....', '....'])), 1);
    });

    test('길게 누운 획에서도 길이가 아니라 두께를 잰다', () {
      final mask = maskFromRows([
        '......................',
        '.####################.',
        '.####################.',
        '.####################.',
        '......................',
      ]);

      expect(estimateLineWidth(mask), 3,
          reason: '길이 20, 두께 3인 획의 두께는 3이다');
    });
  });

  group('경계 처리', () {
    test('침식은 전부 선인 마스크를 그대로 둔다', () {
      final mask = maskFromRows([
        '#####',
        '#####',
        '#####',
        '#####',
        '#####',
      ]);

      expect(erode(mask, 1).inkCount, 25,
          reason: '캔버스 밖을 여백으로 보면 테두리 한 겹이 깎여 나간다');
    });

    test('보정이 테두리에 닿은 선을 잘라내지 않는다', () {
      // 캔버스 가장자리에 딱 붙은 테두리 도형. 침식이 캔버스 밖을 여백으로
      // 보면 이 테두리가 지워지고, 안과 밖이 이어져 색이 새어나간다.
      final mask = maskFromRows([
        '#######',
        '#.....#',
        '#.....#',
        '#.....#',
        '#######',
      ]);

      final closed = closeLines(mask, radius: 1);

      expect(closed.isInk(0, 0), isTrue);
      expect(closed.isInk(3, 0), isTrue);
      expect(closed.isInk(0, 2), isTrue);
      expect(closed.isInk(6, 4), isTrue);
      expect(closed.isInk(3, 2), isFalse,
          reason: '내부는 여전히 칠할 수 있어야 한다');
    });

    test('보정이 캔버스 여백에 없던 선을 만들지 않는다', () {
      // 캔버스 가장자리에서 반지름만큼 떨어진 획. 팽창이 여백까지 자란 뒤
      // 침식이 되돌리지 못하면, 원본에 없던 선이 테두리에 눌어붙는다.
      final mask = maskFromRows([
        '........',
        '..####..',
        '..####..',
        '........',
      ]);

      final closed = closeLines(mask, radius: 1);

      expect(closed.isInk(3, 0), isFalse,
          reason: '위쪽 여백은 여백으로 남아야 한다');
      expect(closed.isInk(3, 3), isFalse,
          reason: '아래쪽 여백은 여백으로 남아야 한다');
      expect(closed.isInk(3, 1), isTrue, reason: '원래 선은 남아야 한다');
    });
  });

  group('dilate / erode', () {
    test('팽창은 선을 반지름만큼 넓힌다', () {
      final mask = maskFromRows([
        '.....',
        '.....',
        '..#..',
        '.....',
        '.....',
      ]);

      final grown = dilate(mask, 1);

      expect(rowsFromMask(grown), [
        '.....',
        '.###.',
        '.###.',
        '.###.',
        '.....',
      ]);
    });

    test('침식은 팽창을 되돌린다', () {
      final mask = maskFromRows([
        '.....',
        '.###.',
        '.###.',
        '.###.',
        '.....',
      ]);

      expect(rowsFromMask(erode(mask, 1)), [
        '.....',
        '.....',
        '..#..',
        '.....',
        '.....',
      ]);
    });
  });

  group('closeLines', () {
    test('끊긴 선의 틈을 메운다', () {
      // 세로선 한가운데가 2픽셀 끊겨 있다. 이대로 라벨링하면 안쪽과 바깥쪽이
      // 하나로 이어져 색이 새어나간다.
      final mask = maskFromRows([
        '.........',
        '....#....',
        '....#....',
        '....#....',
        '.........', // 틈
        '.........', // 틈
        '....#....',
        '....#....',
        '....#....',
        '.........',
      ]);

      expect(mask.isInk(4, 4), isFalse, reason: '보정 전에는 틈이 비어 있다');

      final closed = closeLines(mask, radius: 2);

      expect(closed.isInk(4, 4), isTrue, reason: '틈이 메워져야 한다');
      expect(closed.isInk(4, 5), isTrue, reason: '틈이 메워져야 한다');
    });

    test('반지름을 주지 않으면 선 두께에서 추정한다', () {
      final mask = maskFromRows([
        '..........',
        '..####....',
        '..####....',
        '..........',
        '..####....',
        '..####....',
        '..........',
      ]);

      // 선 두께 4 → 반지름 2 → 세로 1픽셀 틈은 메워진다.
      final closed = closeLines(mask);

      expect(closed.isInk(3, 3), isTrue);
    });

    test('닫힌 도형의 내부를 채우지는 않는다', () {
      final mask = maskFromRows([
        '.........',
        '.#######.',
        '.#.....#.',
        '.#.....#.',
        '.#.....#.',
        '.#######.',
        '.........',
      ]);

      final closed = closeLines(mask, radius: 1);

      expect(closed.isInk(4, 3), isFalse,
          reason: '도형 내부는 여백으로 남아야 칠할 수 있다');
    });
  });
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart test test/morphology_test.dart
```

Expected: FAIL — `Undefined name 'estimateLineWidth'`

- [ ] **Step 4: 최소 구현**

`packages/dohan_core/lib/src/morphology.dart`:

```dart
import 'dart:typed_data';

import 'types.dart';

/// 선 두께를 추정한다.
///
/// 각 선 픽셀에서 가로로 이어진 길이와 세로로 이어진 길이 중 **작은 쪽**을
/// 그 픽셀의 두께로 보고, 전체의 중앙값을 취한다. 가로 런만 재면 길게 누운
/// 획의 *길이*를 두께로 착각해(길이 20의 3픽셀 획 → 20) 보정 반지름이 과도
/// 하게 커지고 가까운 디테일끼리 붙어버린다. 평균이 아니라 중앙값을 쓰는
/// 것은 몇 개의 굵은 덩어리가 통계를 끌어올리는 것을 막기 위해서다.
int estimateLineWidth(BinaryMask mask) {
  final w = mask.width;
  final h = mask.height;
  final horizontal = Int32List(w * h);
  final vertical = Int32List(w * h);

  for (var y = 0; y < h; y++) {
    var x = 0;
    while (x < w) {
      if (mask.ink[y * w + x] == 0) {
        x++;
        continue;
      }
      final start = x;
      while (x < w && mask.ink[y * w + x] == 1) {
        x++;
      }
      for (var i = start; i < x; i++) {
        horizontal[y * w + i] = x - start;
      }
    }
  }

  for (var x = 0; x < w; x++) {
    var y = 0;
    while (y < h) {
      if (mask.ink[y * w + x] == 0) {
        y++;
        continue;
      }
      final start = y;
      while (y < h && mask.ink[y * w + x] == 1) {
        y++;
      }
      for (var i = start; i < y; i++) {
        vertical[i * w + x] = y - start;
      }
    }
  }

  final widths = <int>[];
  for (var i = 0; i < w * h; i++) {
    if (mask.ink[i] == 0) continue;
    final hr = horizontal[i];
    final vr = vertical[i];
    widths.add(hr < vr ? hr : vr);
  }
  if (widths.isEmpty) return 1;
  widths.sort();
  return widths[widths.length ~/ 2];
}

BinaryMask _sweep(
  BinaryMask src,
  int radius, {
  required bool horizontal,
  required bool takeMax,
}) {
  final w = src.width;
  final h = src.height;
  final out = BinaryMask.blank(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var value = takeMax ? 0 : 1;
      for (var d = -radius; d <= radius; d++) {
        final xx = horizontal ? x + d : x;
        final yy = horizontal ? y : y + d;
        // 캔버스 밖은 연산에 따라 다르게 본다. 팽창에서는 여백(0)으로 보아
        // 선이 캔버스 밖으로 자라지 않게 하고, 침식에서는 선(1)으로 보아
        // 경계에 닿은 선이 깎여 사라지지 않게 한다. 둘 다 0으로 두면 침식이
        // 테두리에서 radius 폭만큼 진짜 선을 지워, 보정이 오히려 색이 새는
        // 틈을 만든다.
        final v = (xx < 0 || yy < 0 || xx >= w || yy >= h)
            ? (takeMax ? 0 : 1)
            : src.ink[yy * w + xx];
        if (takeMax && v == 1) {
          value = 1;
          break;
        }
        if (!takeMax && v == 0) {
          value = 0;
          break;
        }
      }
      out.ink[y * w + x] = value;
    }
  }
  return out;
}

/// 사각 구조요소 팽창. 선을 [radius]만큼 사방으로 넓힌다.
BinaryMask dilate(BinaryMask mask, int radius) => _sweep(
      _sweep(mask, radius, horizontal: true, takeMax: true),
      radius,
      horizontal: false,
      takeMax: true,
    );

/// 사각 구조요소 침식. 선을 [radius]만큼 사방에서 깎는다.
BinaryMask erode(BinaryMask mask, int radius) => _sweep(
      _sweep(mask, radius, horizontal: true, takeMax: false),
      radius,
      horizontal: false,
      takeMax: false,
    );

/// 마스크 사방에 [radius]만큼 여백을 덧댄다.
BinaryMask _padWithPaper(BinaryMask src, int radius) {
  final w = src.width + radius * 2;
  final h = src.height + radius * 2;
  final out = BinaryMask.blank(w, h);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      out.ink[(y + radius) * w + (x + radius)] = src.ink[y * src.width + x];
    }
  }
  return out;
}

/// 덧댄 여백을 다시 잘라내 원래 크기로 되돌린다.
BinaryMask _cropPadding(BinaryMask src, int radius, int width, int height) {
  final out = BinaryMask.blank(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      out.ink[y * width + x] = src.ink[(y + radius) * src.width + (x + radius)];
    }
  }
  return out;
}

/// 닫기 연산(팽창 후 침식). 끊긴 선의 틈을 메우되 선 두께는 대체로 보존한다.
///
/// [radius]를 주지 않으면 추정 선 두께의 절반을 쓴다. 이보다 크게 잡으면
/// 가느다란 디테일이 서로 붙어버리고, 작게 잡으면 틈이 남아 색이 샌다.
///
/// 최대 [radius]의 2배 너비까지 틈을 메울 수 있다.
///
/// 캔버스를 반지름만큼 여백으로 넓힌 뒤 팽창·침식하고 다시 잘라낸다. 팽창
/// 결과가 캔버스 밖으로 자란 부분을 잘라버리면 침식이 잘린 면을 경계로
/// 오인해, 테두리의 진짜 선을 깎거나(밖을 여백으로 볼 때) 없던 선을 여백에
/// 눌어붙게 만든다(밖을 선으로 볼 때). 덧댄 뒤 잘라내면 두 경우가 모두
/// 사라지고, 잘라낼 영역 안의 픽셀은 침식할 때 캔버스 밖을 참조하지 않으므로
/// _sweep의 경계 규칙과 무관해진다.
BinaryMask closeLines(BinaryMask mask, {int? radius}) {
  final r = radius ?? (estimateLineWidth(mask) / 2).ceil().clamp(1, 8);
  if (r <= 0) return mask;
  final padded = _padWithPaper(mask, r);
  final closed = erode(dilate(padded, r), r);
  return _cropPadding(closed, r, mask.width, mask.height);
}
```

`packages/dohan_core/lib/dohan_core.dart`에 추가:

```dart
export 'src/morphology.dart';
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test test/morphology_test.dart
```

Expected: PASS — 11개 테스트 통과

- [ ] **Step 6: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): 선 두께 추정과 끊긴 선 보정"
```

---

### Task 4: 연결요소 라벨링

**Files:**
- Create: `packages/dohan_core/lib/src/label_regions.dart`
- Modify: `packages/dohan_core/lib/dohan_core.dart`
- Test: `packages/dohan_core/test/label_regions_test.dart`

**Interfaces:**
- Consumes: `BinaryMask`, `RegionMap`, ID 상수 (Task 1) · `maskFromRows` (Task 3)
- Produces: `labelRegions(BinaryMask) -> RegionMap` — 선 픽셀은 `kRegionLine`, 나머지 연결요소는 `kRegionFirstFillable`부터 순번. 배경 지정은 하지 않는다(Task 5의 책임).

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/dohan_core/test/label_regions_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('labelRegions', () {
    test('선 픽셀은 영역 0을 유지한다', () {
      final map = labelRegions(maskFromRows([
        '.#.',
        '.#.',
      ]));

      expect(map.at(1, 0), kRegionLine);
      expect(map.at(1, 1), kRegionLine);
    });

    test('선이 없으면 여백 전체가 영역 하나다', () {
      final map = labelRegions(maskFromRows([
        '....',
        '....',
      ]));

      expect(map.fillableRegionIds, {kRegionFirstFillable});
    });

    test('세로선이 캔버스를 둘로 가르면 영역이 둘이다', () {
      final map = labelRegions(maskFromRows([
        '..#..',
        '..#..',
        '..#..',
      ]));

      expect(map.fillableRegionCount, 2);
      expect(map.at(0, 0), isNot(map.at(4, 0)),
          reason: '선 왼쪽과 오른쪽은 다른 영역이어야 한다');
    });

    test('닫힌 도형의 안과 밖은 다른 영역이다', () {
      final map = labelRegions(maskFromRows([
        '.......',
        '.#####.',
        '.#...#.',
        '.#...#.',
        '.#####.',
        '.......',
      ]));

      expect(map.fillableRegionCount, 2, reason: '바깥 여백 + 도형 내부');
      expect(map.at(3, 2), isNot(map.at(0, 0)));
    });

    test('대각선으로만 닿은 두 여백은 서로 다른 영역이다', () {
      // 4방 연결을 쓰므로 대각 접촉은 이어지지 않는다. 대각으로 이어진 것을
      // 같은 영역으로 보면, 선이 대각으로 지날 때 색이 새어나간다.
      final map = labelRegions(maskFromRows([
        '.#',
        '#.',
      ]));

      expect(map.fillableRegionCount, 2);
    });

    test('영역 ID는 2부터 빈틈없이 부여된다', () {
      final map = labelRegions(maskFromRows([
        '.#.#.',
        '.#.#.',
      ]));

      expect(map.fillableRegionIds, {2, 3, 4});
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart test test/label_regions_test.dart
```

Expected: FAIL — `Undefined name 'labelRegions'`

- [ ] **Step 3: 최소 구현**

`packages/dohan_core/lib/src/label_regions.dart`:

```dart
import 'dart:typed_data';

import 'types.dart';

/// 선이 아닌 픽셀을 4방 연결 기준으로 묶어 영역 ID를 부여한다.
///
/// 선 픽셀은 [kRegionLine]으로 남고, 연결요소는 [kRegionFirstFillable]부터
/// 빈틈없이 번호를 받는다. 어느 영역이 배경인지는 여기서 판단하지 않는다 —
/// 그것은 cleanupRegions의 책임이다.
///
/// 8방이 아니라 4방 연결을 쓰는 이유는, 대각으로 이어진 여백을 같은 영역으로
/// 보면 선이 대각으로 지나는 곳마다 색이 새어나가기 때문이다.
RegionMap labelRegions(BinaryMask mask) {
  final w = mask.width;
  final h = mask.height;
  final labels = Int32List(w * h); // 0 = 아직 라벨 없음

  // union-find. parent[i]의 인덱스가 임시 라벨 번호다.
  final parent = <int>[0];

  int find(int a) {
    while (parent[a] != a) {
      parent[a] = parent[parent[a]]; // 경로 절반 압축
      a = parent[a];
    }
    return a;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    if (ra < rb) {
      parent[rb] = ra;
    } else {
      parent[ra] = rb;
    }
  }

  var next = 1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (mask.ink[i] == 1) continue;

      final left = (x > 0 && mask.ink[i - 1] == 0) ? labels[i - 1] : 0;
      final up = (y > 0 && mask.ink[i - w] == 0) ? labels[i - w] : 0;

      if (left == 0 && up == 0) {
        labels[i] = next;
        parent.add(next);
        next++;
      } else if (left != 0 && up != 0) {
        labels[i] = left < up ? left : up;
        union(left, up);
      } else {
        labels[i] = left != 0 ? left : up;
      }
    }
  }

  // 2차 패스: 대표 라벨로 정규화하고 ID를 2부터 연속 부여한다.
  final remap = <int, int>{};
  var nextId = kRegionFirstFillable;
  final out = RegionMap.filled(w, h, kRegionLine);
  for (var i = 0; i < w * h; i++) {
    if (labels[i] == 0) continue;
    final root = find(labels[i]);
    final id = remap.putIfAbsent(root, () {
      if (nextId > kMaxRegionId) {
        throw StateError(
            '영역이 $kMaxRegionId개를 넘었습니다. 입력 선화가 너무 복잡하거나 '
            '노이즈가 많습니다.');
      }
      return nextId++;
    });
    out.ids[i] = id;
  }
  return out;
}
```

`packages/dohan_core/lib/dohan_core.dart`에 추가:

```dart
export 'src/label_regions.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test test/label_regions_test.dart
```

Expected: PASS — 6개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): union-find 연결요소 라벨링"
```

---

### Task 5: 영역 정리 — 배경 지정과 파편 병합

**Files:**
- Create: `packages/dohan_core/lib/src/cleanup.dart`
- Modify: `packages/dohan_core/lib/dohan_core.dart`
- Test: `packages/dohan_core/test/cleanup_test.dart`

**Interfaces:**
- Consumes: `RegionMap`, ID 상수 (Task 1) · `labelRegions` (Task 4)
- Produces: `cleanupRegions(RegionMap, {required int minArea, int searchRadius}) -> RegionMap` — 캔버스 테두리에 닿는 영역을 `kRegionBackground`로 바꾸고, `minArea` 미만 파편을 가장 넓게 맞닿은 이웃에 병합한 뒤, 남은 영역에 ID를 2부터 다시 부여한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/dohan_core/test/cleanup_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('cleanupRegions', () {
    test('캔버스 테두리에 닿은 영역은 배경이 된다', () {
      final labeled = labelRegions(maskFromRows([
        '.......',
        '.#####.',
        '.#...#.',
        '.#...#.',
        '.#####.',
        '.......',
      ]));

      final cleaned = cleanupRegions(labeled, minArea: 1);

      expect(cleaned.at(0, 0), kRegionBackground, reason: '바깥 여백은 배경');
      expect(cleaned.at(3, 2), greaterThanOrEqualTo(kRegionFirstFillable),
          reason: '도형 내부는 칠할 수 있어야 한다');
      expect(cleaned.fillableRegionCount, 1);
    });

    test('배경으로 둘러싸인 도형이 여럿이면 각각 살아남는다', () {
      final labeled = labelRegions(maskFromRows([
        '............',
        '.###...###..',
        '.#.#...#.#..',
        '.###...###..',
        '............',
      ]));

      final cleaned = cleanupRegions(labeled, minArea: 1);

      expect(cleaned.fillableRegionCount, 2);
      expect(cleaned.at(2, 2), isNot(cleaned.at(8, 2)));
    });

    test('넓이가 기준 미만인 파편은 이웃 영역에 흡수된다', () {
      // 큰 방 하나와, 선 하나 건너 붙어 있는 1픽셀짜리 파편.
      final labeled = labelRegions(maskFromRows([
        '..........',
        '.########.',
        '.#......#.',
        '.#......#.',
        '.#......#.',
        '.########.',
        '.#.#......',
        '.###......',
        '..........',
      ]));

      final before = labeled.fillableRegionCount;
      final cleaned = cleanupRegions(labeled, minArea: 4, searchRadius: 3);

      expect(before, greaterThan(1));
      expect(cleaned.fillableRegionCount, 1,
          reason: '1픽셀 파편은 사라지고 큰 방만 남아야 한다');
    });

    test('정리 후 영역 ID는 2부터 빈틈없이 다시 부여된다', () {
      final labeled = labelRegions(maskFromRows([
        '............',
        '.###...###..',
        '.#.#...#.#..',
        '.###...###..',
        '............',
      ]));

      final cleaned = cleanupRegions(labeled, minArea: 1);

      expect(cleaned.fillableRegionIds, {2, 3});
    });

    test('칠할 수 있는 영역이 하나도 없어도 예외를 던지지 않는다', () {
      final labeled = labelRegions(maskFromRows([
        '....',
        '....',
      ]));

      final cleaned = cleanupRegions(labeled, minArea: 1);

      expect(cleaned.fillableRegionCount, 0);
      expect(cleaned.at(0, 0), kRegionBackground);
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart test test/cleanup_test.dart
```

Expected: FAIL — `Undefined name 'cleanupRegions'`

- [ ] **Step 3: 최소 구현**

`packages/dohan_core/lib/src/cleanup.dart`:

```dart
import 'dart:typed_data';

import 'types.dart';

/// 배경을 지정하고 파편을 병합한 뒤 영역 ID를 다시 부여한다.
///
/// - 캔버스 테두리에 닿은 연결요소는 모두 [kRegionBackground]가 된다.
///   도안 바깥 여백이 여기에 해당하며, 칠할 수 없다.
/// - 넓이가 [minArea] 미만인 영역은 [searchRadius] 안에서 가장 많이 마주친
///   다른 영역에 흡수된다. 선을 사이에 두고 떨어져 있어도 흡수되도록
///   반경 탐색을 쓴다 — 영역끼리는 선으로 갈라져 있어 서로 인접하지 않는다.
/// - 흡수 대상이 배경뿐이면 그 파편은 배경이 된다.
///
/// 파편이 사슬처럼 이어진 경우를 위해 안정될 때까지 최대 4회 반복한다.
RegionMap cleanupRegions(
  RegionMap src, {
  required int minArea,
  int searchRadius = 3,
}) {
  final w = src.width;
  final h = src.height;
  final ids = Uint16List.fromList(src.ids);

  // 1) 테두리에 닿은 영역을 배경으로 바꾼다.
  final borderIds = <int>{};
  for (var x = 0; x < w; x++) {
    borderIds.add(ids[x]);
    borderIds.add(ids[(h - 1) * w + x]);
  }
  for (var y = 0; y < h; y++) {
    borderIds.add(ids[y * w]);
    borderIds.add(ids[y * w + w - 1]);
  }
  borderIds.removeWhere((id) => id < kRegionFirstFillable);
  if (borderIds.isNotEmpty) {
    for (var i = 0; i < ids.length; i++) {
      if (borderIds.contains(ids[i])) ids[i] = kRegionBackground;
    }
  }

  // 2) 작은 파편을 이웃에 흡수시킨다.
  for (var pass = 0; pass < 4; pass++) {
    final areas = <int, int>{};
    for (final id in ids) {
      if (id >= kRegionFirstFillable) areas[id] = (areas[id] ?? 0) + 1;
    }
    final tooSmall = areas.entries
        .where((e) => e.value < minArea)
        .map((e) => e.key)
        .toSet();
    if (tooSmall.isEmpty) break;

    var changed = false;
    for (final victim in tooSmall) {
      final target = _dominantNeighbor(ids, w, h, victim, searchRadius);
      if (target == victim) continue;
      for (var i = 0; i < ids.length; i++) {
        if (ids[i] == victim) ids[i] = target;
      }
      changed = true;
    }
    if (!changed) break;
  }

  // 3) 남은 영역에 ID를 2부터 다시 부여한다.
  final remap = <int, int>{};
  var nextId = kRegionFirstFillable;
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i];
    if (id < kRegionFirstFillable) continue;
    ids[i] = remap.putIfAbsent(id, () => nextId++);
  }

  return RegionMap(w, h, ids);
}

/// [victim] 영역의 픽셀 주변 [radius] 안에서 가장 자주 마주치는 다른 영역 ID.
/// 후보가 없으면 [kRegionBackground]를 돌려준다.
int _dominantNeighbor(
  Uint16List ids,
  int w,
  int h,
  int victim,
  int radius,
) {
  final votes = <int, int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (ids[y * w + x] != victim) continue;
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          final xx = x + dx;
          final yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          final other = ids[yy * w + xx];
          if (other == victim || other == kRegionLine) continue;
          votes[other] = (votes[other] ?? 0) + 1;
        }
      }
    }
  }
  if (votes.isEmpty) return kRegionBackground;

  // 칠할 수 있는 이웃을 배경보다 우선한다. 파편이 도형 안쪽에 있으면
  // 배경으로 삼키는 것보다 이웃 영역에 합치는 편이 결과가 낫다.
  var best = kRegionBackground;
  var bestVotes = -1;
  for (final entry in votes.entries) {
    final weight = entry.key >= kRegionFirstFillable
        ? entry.value * 2
        : entry.value;
    if (weight > bestVotes) {
      bestVotes = weight;
      best = entry.key;
    }
  }
  return best;
}
```

`packages/dohan_core/lib/dohan_core.dart`에 추가:

```dart
export 'src/cleanup.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test test/cleanup_test.dart
```

Expected: PASS — 5개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): 배경 지정과 파편 병합"
```

---

### Task 6: 품질 게이트

**Files:**
- Create: `packages/dohan_core/lib/src/quality_gate.dart`
- Modify: `packages/dohan_core/lib/dohan_core.dart`
- Test: `packages/dohan_core/test/quality_gate_test.dart`

**Interfaces:**
- Consumes: `RegionMap`, ID 상수 (Task 1)
- Produces: `QualityIssue` enum (`tooFewRegions`, `tooManyRegions`, `backgroundTooSmall`, `regionTooSmallToTap`) · `QualityThresholds` · `QualityReport` (필드 `regionCount`, `backgroundRatio`, `smallestTapDiameter`, `issues`; getter `passed`; 메서드 `koreanSummary()`) · `evaluateQuality(RegionMap, {QualityThresholds thresholds}) -> QualityReport`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/dohan_core/test/quality_gate_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// 배경 안에 [count]개의 정사각형 방이 있는 맵을 만든다.
/// 각 방의 내부는 [inner]×[inner] 픽셀이다.
RegionMap _roomsMap({required int count, int inner = 10}) {
  const margin = 2;
  final cell = inner + 2; // 방 하나 + 테두리 선
  final w = margin * 2 + count * (cell + 1);
  final h = margin * 2 + cell;
  final rows = <String>[];
  for (var y = 0; y < h; y++) {
    final buf = StringBuffer();
    for (var x = 0; x < w; x++) {
      var ink = false;
      for (var k = 0; k < count; k++) {
        final x0 = margin + k * (cell + 1);
        final y0 = margin;
        final onV = (x == x0 || x == x0 + cell - 1) &&
            y >= y0 && y <= y0 + cell - 1;
        final onH = (y == y0 || y == y0 + cell - 1) &&
            x >= x0 && x <= x0 + cell - 1;
        if (onV || onH) ink = true;
      }
      buf.write(ink ? '#' : '.');
    }
    rows.add(buf.toString());
  }
  return cleanupRegions(labelRegions(maskFromRows(rows)), minArea: 1);
}

void main() {
  group('evaluateQuality', () {
    test('영역이 4개 미만이면 리젝트한다', () {
      final report = evaluateQuality(_roomsMap(count: 2));

      expect(report.passed, isFalse);
      expect(report.issues, contains(QualityIssue.tooFewRegions));
      expect(report.regionCount, 2);
    });

    test('영역이 120개를 넘으면 리젝트한다', () {
      final report = evaluateQuality(
        _roomsMap(count: 6),
        thresholds: const QualityThresholds(maxRegions: 5),
      );

      expect(report.passed, isFalse);
      expect(report.issues, contains(QualityIssue.tooManyRegions));
    });

    test('배경이 캔버스의 60% 미만이면 선이 샌다고 본다', () {
      // 선이 없는 맵. cleanupRegions가 전부 배경으로 만들면 배경 비율은 1.0.
      // 반대로 배경이 거의 없는 맵을 만들어 판정을 확인한다.
      final map = RegionMap.filled(10, 10, kRegionFirstFillable);
      for (var x = 0; x < 10; x++) {
        map.set(x, 0, kRegionBackground);
      }

      final report = evaluateQuality(map);

      expect(report.backgroundRatio, closeTo(0.10, 0.001));
      expect(report.issues, contains(QualityIssue.backgroundTooSmall));
    });

    test('손가락으로 누를 수 없는 영역이 있으면 표시한다', () {
      final report = evaluateQuality(
        _roomsMap(count: 5, inner: 4),
        thresholds: const QualityThresholds(
          minBackgroundRatio: 0.0,
          minTapDiameterPx: 20,
        ),
      );

      expect(report.smallestTapDiameter, lessThan(20));
      expect(report.issues, contains(QualityIssue.regionTooSmallToTap));
    });

    test('기준을 모두 만족하면 통과한다', () {
      final report = evaluateQuality(
        _roomsMap(count: 5, inner: 10),
        thresholds: const QualityThresholds(
          minBackgroundRatio: 0.0,
          minTapDiameterPx: 4,
        ),
      );

      expect(report.issues, isEmpty);
      expect(report.passed, isTrue);
      expect(report.regionCount, 5);
    });

    test('한국어 요약에 실패 사유가 담긴다', () {
      final report = evaluateQuality(_roomsMap(count: 2));

      expect(report.koreanSummary(), contains('영역'));
      expect(report.koreanSummary(), isNot(contains('null')));
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart test test/quality_gate_test.dart
```

Expected: FAIL — `Undefined name 'evaluateQuality'`

- [ ] **Step 3: 최소 구현**

`packages/dohan_core/lib/src/quality_gate.dart`:

```dart
import 'dart:collection';
import 'dart:typed_data';

import 'types.dart';

/// 도안이 아이에게 쓸 만한지 판정할 때 걸리는 항목.
enum QualityIssue {
  /// 영역이 너무 적다. 라벨링이 실패했거나 도안이 지나치게 단순하다.
  tooFewRegions,

  /// 영역이 너무 많다. 선이 지저분해 아이가 칠하기 어렵다.
  tooManyRegions,

  /// 배경이 너무 좁다. 선이 끊겨 색이 새고 있다는 신호다.
  backgroundTooSmall,

  /// 손가락으로 누를 수 없을 만큼 작은 영역이 있다.
  regionTooSmallToTap,
}

/// 품질 게이트 기준값.
///
/// [minTapDiameterPx]는 1024px 캔버스 기준 픽셀 수다. 기본값 72는 폰에서
/// 캔버스가 약 340dp로 표시될 때의 24dp에 해당한다. UI 버튼의 64dp 최소
/// 터치 타겟과는 다른 기준이다 — 도안 디테일에 64dp를 적용하면 공룡 발톱
/// 같은 정상적인 영역이 전부 병합된다.
class QualityThresholds {
  final int minRegions;
  final int maxRegions;
  final double minBackgroundRatio;
  final int minTapDiameterPx;

  const QualityThresholds({
    this.minRegions = 4,
    this.maxRegions = 120,
    this.minBackgroundRatio = 0.60,
    this.minTapDiameterPx = 72,
  });
}

/// 품질 게이트 판정 결과.
class QualityReport {
  final int regionCount;
  final double backgroundRatio;
  final int smallestTapDiameter;
  final List<QualityIssue> issues;

  const QualityReport({
    required this.regionCount,
    required this.backgroundRatio,
    required this.smallestTapDiameter,
    required this.issues,
  });

  bool get passed => issues.isEmpty;

  /// 사람이 읽을 판정 요약.
  String koreanSummary() {
    if (issues.isEmpty) {
      return '통과 — 영역 $regionCount개, 배경 '
          '${(backgroundRatio * 100).toStringAsFixed(1)}%, '
          '최소 영역 지름 ${smallestTapDiameter}px';
    }
    final reasons = issues.map((i) {
      switch (i) {
        case QualityIssue.tooFewRegions:
          return '칠할 수 있는 영역이 $regionCount개뿐입니다';
        case QualityIssue.tooManyRegions:
          return '영역이 $regionCount개로 너무 많습니다';
        case QualityIssue.backgroundTooSmall:
          return '배경이 ${(backgroundRatio * 100).toStringAsFixed(1)}%뿐입니다 '
              '(선이 끊겨 색이 새고 있을 수 있습니다)';
        case QualityIssue.regionTooSmallToTap:
          return '가장 작은 영역의 지름이 ${smallestTapDiameter}px로 '
              '손가락으로 누르기 어렵습니다';
      }
    });
    return '리젝트 — ${reasons.join(' / ')}';
  }
}

/// 영역 맵이 품질 기준을 만족하는지 판정한다.
QualityReport evaluateQuality(
  RegionMap map, {
  QualityThresholds thresholds = const QualityThresholds(),
}) {
  final areas = map.areaByRegion();
  final total = map.width * map.height;
  final regionCount = map.fillableRegionCount;
  final backgroundRatio = (areas[kRegionBackground] ?? 0) / total;
  final smallest = _smallestInscribedDiameter(map);

  final issues = <QualityIssue>[];
  if (regionCount < thresholds.minRegions) {
    issues.add(QualityIssue.tooFewRegions);
  }
  if (regionCount > thresholds.maxRegions) {
    issues.add(QualityIssue.tooManyRegions);
  }
  if (backgroundRatio < thresholds.minBackgroundRatio) {
    issues.add(QualityIssue.backgroundTooSmall);
  }
  if (regionCount > 0 && smallest < thresholds.minTapDiameterPx) {
    issues.add(QualityIssue.regionTooSmallToTap);
  }

  return QualityReport(
    regionCount: regionCount,
    backgroundRatio: backgroundRatio,
    smallestTapDiameter: smallest,
    issues: issues,
  );
}

/// 칠할 수 있는 영역들의 내접원 지름 중 가장 작은 값.
///
/// 영역 경계에서 시작하는 8방 BFS로 체비셰프 거리 변환을 구한다. 체비셰프
/// 거리의 최대값은 내접 정사각형의 반지름이므로, 지름은 그 2배 + 1이다.
/// 원이 아니라 정사각형이지만 판정 목적에는 충분하다.
///
/// 외접원이 아니라 내접원을 쓰는 이유는, 가늘고 긴 영역은 외접원이 커도
/// 손가락으로 누를 수 없기 때문이다.
int _smallestInscribedDiameter(RegionMap map) {
  final w = map.width;
  final h = map.height;
  final dist = Int32List(w * h)..fillRange(0, w * h, -1);
  final queue = Queue<int>();

  // 자기 영역이 아닌 이웃을 가졌거나 캔버스 경계에 있는 픽셀이 거리 0이다.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final id = map.ids[i];
      if (id < kRegionFirstFillable) continue;
      var isEdge = x == 0 || y == 0 || x == w - 1 || y == h - 1;
      if (!isEdge) {
        outer:
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (map.ids[(y + dy) * w + (x + dx)] != id) {
              isEdge = true;
              break outer;
            }
          }
        }
      }
      if (isEdge) {
        dist[i] = 0;
        queue.add(i);
      }
    }
  }

  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    final x = i % w;
    final y = i ~/ w;
    final id = map.ids[i];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final xx = x + dx;
        final yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        final j = yy * w + xx;
        if (map.ids[j] != id) continue;
        if (dist[j] != -1) continue;
        dist[j] = dist[i] + 1;
        queue.add(j);
      }
    }
  }

  final maxPerRegion = <int, int>{};
  for (var i = 0; i < w * h; i++) {
    final id = map.ids[i];
    if (id < kRegionFirstFillable) continue;
    final d = dist[i];
    if (d > (maxPerRegion[id] ?? -1)) maxPerRegion[id] = d;
  }
  if (maxPerRegion.isEmpty) return 0;

  var smallest = 1 << 30;
  for (final radius in maxPerRegion.values) {
    final diameter = radius * 2 + 1;
    if (diameter < smallest) smallest = diameter;
  }
  return smallest;
}
```

`packages/dohan_core/lib/dohan_core.dart`에 추가:

```dart
export 'src/quality_gate.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test test/quality_gate_test.dart
```

Expected: PASS — 6개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): 품질 게이트와 내접원 지름 판정"
```

---

### Task 7: 인덱스맵 PNG와 도안 패키지 입출력

**Files:**
- Create: `packages/dohan_core/lib/src/index_map.dart`
- Create: `packages/dohan_core/lib/src/dohan_package.dart`
- Modify: `packages/dohan_core/lib/dohan_core.dart`
- Test: `packages/dohan_core/test/index_map_test.dart`
- Test: `packages/dohan_core/test/dohan_package_test.dart`

**Interfaces:**
- Consumes: `RegionMap`, `encodeRegionId`, `decodeRegionId` (Task 1)
- Produces: `encodeIndexMapPng(RegionMap) -> Uint8List` · `decodeIndexMapPng(Uint8List) -> RegionMap` · `DohanMeta` (필드 `id`, `title`, `category`, `source`, `canvasSize`, `regionCount`, `difficulty`, `suggestedPalette`, `regionCentroids`, `createdAt`; `toJson()`, `DohanMeta.fromJson`) · `writeDohanPackage({required Directory dir, required img.Image lineart, required RegionMap regions, required DohanMeta meta}) -> Future<void>` · `readDohanPackage(Directory) -> Future<DohanPackage>` · `computeRegionCentroids(RegionMap) -> Map<int, List<int>>`

- [ ] **Step 1: 실패하는 테스트 작성 — 인덱스맵**

`packages/dohan_core/test/index_map_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  group('인덱스맵 PNG', () {
    test('영역 ID가 손실 없이 왕복한다', () {
      final map = RegionMap.filled(8, 4, kRegionBackground);
      map.set(0, 0, kRegionLine);
      map.set(1, 0, 2);
      map.set(2, 0, 255);
      map.set(3, 0, 256);
      map.set(4, 0, 4096);
      map.set(5, 0, 65535);

      final restored = decodeIndexMapPng(encodeIndexMapPng(map));

      expect(restored.width, 8);
      expect(restored.height, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 8; x++) {
          expect(restored.at(x, y), map.at(x, y),
              reason: '($x, $y) 왕복 실패');
        }
      }
    });

    test('B 채널은 0, A 채널은 255로 기록된다', () {
      final map = RegionMap.filled(2, 2, 300);

      final im = img.decodePng(encodeIndexMapPng(map))!;
      final p = im.getPixel(0, 0);

      expect(p.r.toInt(), 300 & 0xFF);
      expect(p.g.toInt(), 300 >> 8);
      expect(p.b.toInt(), 0);
      expect(p.a.toInt(), 255);
    });

    test('1024×1024 맵도 왕복한다', () {
      final map = RegionMap.filled(1024, 1024, kRegionBackground);
      for (var i = 0; i < 1024; i++) {
        map.set(i, i, kRegionFirstFillable + (i % 500));
      }

      final restored = decodeIndexMapPng(encodeIndexMapPng(map));

      for (var i = 0; i < 1024; i += 37) {
        expect(restored.at(i, i), map.at(i, i));
      }
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart test test/index_map_test.dart
```

Expected: FAIL — `Undefined name 'encodeIndexMapPng'`

- [ ] **Step 3: 인덱스맵 구현**

`packages/dohan_core/lib/src/index_map.dart`:

```dart
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'types.dart';

/// 영역 맵을 무손실 PNG로 인코딩한다.
///
/// 색상 이미지가 아니라 데이터다. 리샘플링, 손실 압축, 팔레트 양자화를
/// 거치면 영역 ID가 손상되므로 이 함수가 만든 바이트를 그대로 저장해야 한다.
Uint8List encodeIndexMapPng(RegionMap map) {
  final im = img.Image(width: map.width, height: map.height, numChannels: 4);
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final rgba = encodeRegionId(map.at(x, y));
      im.setPixelRgba(x, y, rgba[0], rgba[1], rgba[2], rgba[3]);
    }
  }
  return img.encodePng(im, level: 9);
}

/// 인덱스맵 PNG에서 영역 맵을 복원한다.
RegionMap decodeIndexMapPng(Uint8List bytes) {
  final im = img.decodePng(bytes);
  if (im == null) {
    throw const FormatException('인덱스맵 PNG를 디코딩할 수 없습니다.');
  }
  final map = RegionMap.filled(im.width, im.height, kRegionLine);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      map.set(x, y, decodeRegionId(p.r.toInt(), p.g.toInt()));
    }
  }
  return map;
}
```

- [ ] **Step 4: 실패하는 테스트 작성 — 패키지 입출력**

`packages/dohan_core/test/dohan_package_test.dart`:

```dart
import 'dart:io';

import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('dohan_pkg_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('computeRegionCentroids', () {
    test('영역별 중심 좌표를 계산한다', () {
      final map = RegionMap.filled(6, 2, kRegionBackground);
      map.set(0, 0, 2);
      map.set(2, 0, 2);
      map.set(4, 1, 3);

      final centroids = computeRegionCentroids(map);

      expect(centroids[2], [1, 0]);
      expect(centroids[3], [4, 1]);
      expect(centroids.containsKey(kRegionBackground), isFalse);
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
        regionCentroids: {2: [412, 330]},
        createdAt: DateTime.utc(2026, 9, 21),
      );

      final restored = DohanMeta.fromJson(meta.toJson());

      expect(restored.id, meta.id);
      expect(restored.title, meta.title);
      expect(restored.category, meta.category);
      expect(restored.canvasSize, meta.canvasSize);
      expect(restored.regionCount, 23);
      expect(restored.suggestedPalette, ['#63b98b', '#f1bd45']);
      expect(restored.regionCentroids[2], [412, 330]);
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
        regionCentroids: computeRegionCentroids(regions),
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
          regionCentroids: const {},
          createdAt: DateTime.utc(2026, 9, 21),
        ),
      );

      final text = File('${tmp.path}/meta.json').readAsStringSync();

      expect(text, contains('\n  "id"'));
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
        '"suggestedPalette":[],"regionCentroids":{},'
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
```

- [ ] **Step 5: 패키지 입출력 구현**

`packages/dohan_core/lib/src/dohan_package.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'index_map.dart';
import 'types.dart';

/// 도안 패키지의 메타데이터. `meta.json`으로 직렬화된다.
class DohanMeta {
  final String id;
  final String title;

  /// `animal` · `car` · `dinosaur` · `character` 중 하나.
  final String category;

  /// `bundled`(앱 내장) 또는 `user`(사용자가 사진에서 변환).
  final String source;

  final List<int> canvasSize;
  final int regionCount;
  final int difficulty;
  final List<String> suggestedPalette;

  /// 영역 ID → [x, y] 중심 좌표. 미완성 영역 힌트 표시에 쓴다.
  final Map<int, List<int>> regionCentroids;

  final DateTime createdAt;

  const DohanMeta({
    required this.id,
    required this.title,
    required this.category,
    required this.source,
    required this.canvasSize,
    required this.regionCount,
    required this.difficulty,
    required this.suggestedPalette,
    required this.regionCentroids,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'source': source,
        'canvasSize': canvasSize,
        'regionCount': regionCount,
        'difficulty': difficulty,
        'suggestedPalette': suggestedPalette,
        'regionCentroids': {
          for (final e in regionCentroids.entries) e.key.toString(): e.value
        },
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory DohanMeta.fromJson(Map<String, dynamic> json) => DohanMeta(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String,
        source: json['source'] as String,
        canvasSize: (json['canvasSize'] as List).cast<int>(),
        regionCount: json['regionCount'] as int,
        difficulty: json['difficulty'] as int,
        suggestedPalette: (json['suggestedPalette'] as List).cast<String>(),
        regionCentroids: {
          for (final e in (json['regionCentroids'] as Map).entries)
            int.parse(e.key as String): (e.value as List).cast<int>()
        },
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// 디스크에서 읽어 들인 도안 한 벌.
class DohanPackage {
  final DohanMeta meta;
  final img.Image lineart;
  final RegionMap regions;

  const DohanPackage({
    required this.meta,
    required this.lineart,
    required this.regions,
  });
}

/// 칠할 수 있는 영역별 픽셀 중심 좌표를 구한다.
Map<int, List<int>> computeRegionCentroids(RegionMap map) {
  final sumX = <int, int>{};
  final sumY = <int, int>{};
  final count = <int, int>{};
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final id = map.at(x, y);
      if (id < kRegionFirstFillable) continue;
      sumX[id] = (sumX[id] ?? 0) + x;
      sumY[id] = (sumY[id] ?? 0) + y;
      count[id] = (count[id] ?? 0) + 1;
    }
  }
  return {
    for (final id in count.keys)
      id: [sumX[id]! ~/ count[id]!, sumY[id]! ~/ count[id]!]
  };
}

/// 도안 패키지 세 파일을 [dir]에 쓴다.
Future<void> writeDohanPackage({
  required Directory dir,
  required img.Image lineart,
  required RegionMap regions,
  required DohanMeta meta,
}) async {
  await dir.create(recursive: true);
  await File('${dir.path}/lineart.png')
      .writeAsBytes(img.encodePng(lineart, level: 9));
  await File('${dir.path}/regions.png')
      .writeAsBytes(encodeIndexMapPng(regions));
  await File('${dir.path}/meta.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(meta.toJson()),
  );
}

Future<Uint8List> _readBytes(Directory dir, String name) async {
  try {
    return await File('${dir.path}/$name').readAsBytes();
  } on FileSystemException catch (e) {
    throw FormatException('$name 파일을 열 수 없습니다 (${dir.path}): ${e.message}');
  }
}

Future<String> _readText(Directory dir, String name) async {
  try {
    return await File('${dir.path}/$name').readAsString();
  } on FileSystemException catch (e) {
    throw FormatException('$name 파일을 열 수 없습니다 (${dir.path}): ${e.message}');
  }
}

/// [dir]의 도안 패키지를 읽는다.
///
/// 어느 파일에서 실패했는지 한국어로 알려준다. 앱이 사용자에게 보여줄 안내를
/// 고르려면 파일 단위로 원인을 구분할 수 있어야 한다.
Future<DohanPackage> readDohanPackage(Directory dir) async {
  final metaText = await _readText(dir, 'meta.json');
  final DohanMeta meta;
  try {
    meta = DohanMeta.fromJson(jsonDecode(metaText) as Map<String, dynamic>);
  } catch (e) {
    throw FormatException('meta.json의 내용을 해석할 수 없습니다 (${dir.path}): $e');
  }

  final lineartBytes = await _readBytes(dir, 'lineart.png');
  final lineart = img.decodePng(lineartBytes);
  if (lineart == null) {
    throw FormatException('lineart.png를 디코딩할 수 없습니다 (${dir.path}).');
  }

  final regionBytes = await _readBytes(dir, 'regions.png');

  return DohanPackage(
    meta: meta,
    lineart: lineart,
    regions: decodeIndexMapPng(regionBytes),
  );
}
```

`packages/dohan_core/lib/dohan_core.dart`에 추가:

```dart
export 'src/index_map.dart';
export 'src/dohan_package.dart';
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test test/index_map_test.dart test/dohan_package_test.dart
```

Expected: PASS — 10개 테스트 통과 (index_map 3 + dohan_package 7)

- [ ] **Step 7: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): 인덱스맵 PNG와 도안 패키지 입출력"
```

---

### Task 8: 파이프라인 조립과 누수 회귀 테스트

이 태스크의 누수 회귀 테스트가 계획 전체에서 가장 중요한 테스트다. 이 테스트가 깨지면 아이가 공룡 등을 칠했을 때 배경까지 초록이 된다.

**Files:**
- Create: `packages/dohan_core/lib/src/pipeline.dart`
- Modify: `packages/dohan_core/lib/dohan_core.dart`
- Test: `packages/dohan_core/test/pipeline_test.dart`

**Interfaces:**
- Consumes: `binarize` (Task 2) · `closeLines` (Task 3) · `labelRegions` (Task 4) · `cleanupRegions` (Task 5) · `evaluateQuality`, `QualityThresholds` (Task 6)
- Produces: `PipelineOptions` (필드 `binarizeWindow`, `binarizeOffset`, `closeRadius`, `minRegionArea`, `neighborSearchRadius`, `thresholds`) · `PipelineResult` (필드 `ink`, `regions`, `quality`) · `runPipeline(img.Image, {PipelineOptions options}) -> PipelineResult`

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/dohan_core/test/pipeline_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// 흰 배경 위에 검은 테두리 사각형을 그린 이미지.
/// [gapWidth]만큼 테두리 위쪽을 비워 "끊긴 선"을 만든다.
img.Image _boxImage({
  int size = 128,
  int inset = 24,
  int stroke = 3,
  int gapWidth = 0,
}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
  final lo = inset;
  final hi = size - inset - 1;
  final gapFrom = size ~/ 2 - gapWidth ~/ 2;
  final gapTo = gapFrom + gapWidth;

  void ink(int x, int y) {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    im.setPixelRgba(x, y, 0, 0, 0, 255);
  }

  for (var t = 0; t < stroke; t++) {
    for (var x = lo; x <= hi; x++) {
      if (!(x >= gapFrom && x < gapTo)) ink(x, lo + t); // 위 (여기에 틈)
      ink(x, hi - t); // 아래
    }
    for (var y = lo; y <= hi; y++) {
      ink(lo + t, y);
      ink(hi - t, y);
    }
  }
  return im;
}

void main() {
  const lenient = QualityThresholds(
    minRegions: 1,
    maxRegions: 120,
    minBackgroundRatio: 0.0,
    minTapDiameterPx: 4,
  );

  group('runPipeline', () {
    test('닫힌 사각형은 안과 밖이 분리된다', () {
      final result = runPipeline(
        _boxImage(),
        options: const PipelineOptions(thresholds: lenient),
      );

      expect(result.regions.fillableRegionCount, 1,
          reason: '바깥은 배경이 되고 내부 하나만 칠할 수 있어야 한다');
      expect(result.regions.at(64, 64),
          greaterThanOrEqualTo(kRegionFirstFillable));
      expect(result.regions.at(1, 1), kRegionBackground);
    });

    test('선 보정을 끄면 끊긴 사각형에서 색이 샌다 (회귀 기준선)', () {
      final result = runPipeline(
        _boxImage(gapWidth: 4),
        options: const PipelineOptions(
          closeRadius: 0,
          thresholds: lenient,
        ),
      );

      // 틈으로 안과 밖이 이어져 하나의 연결요소가 되고, 그것이 캔버스
      // 테두리에 닿으므로 전부 배경이 된다 = 칠할 곳이 없다.
      expect(result.regions.fillableRegionCount, 0,
          reason: '보정을 끄면 내부가 배경에 삼켜진다');
      expect(result.regions.at(64, 64), kRegionBackground);
    });

    test('선 보정을 켜면 끊긴 사각형도 내부가 살아난다 (누수 회귀 테스트)', () {
      final result = runPipeline(
        _boxImage(gapWidth: 4),
        options: const PipelineOptions(
          closeRadius: 3,
          thresholds: lenient,
        ),
      );

      expect(result.regions.fillableRegionCount, 1,
          reason: '틈이 메워져 내부가 독립 영역이 되어야 한다');
      expect(result.regions.at(64, 64),
          greaterThanOrEqualTo(kRegionFirstFillable),
          reason: '사각형 한가운데는 칠할 수 있어야 한다');
      expect(result.regions.at(1, 1), kRegionBackground,
          reason: '바깥은 배경이어야 한다');
    });

    test('누수가 나면 품질 게이트가 잡아낸다', () {
      final result = runPipeline(
        _boxImage(gapWidth: 4),
        options: const PipelineOptions(closeRadius: 0),
      );

      expect(result.quality.passed, isFalse);
      expect(result.quality.issues, contains(QualityIssue.tooFewRegions));
    });

    test('결과에 이진 마스크와 품질 리포트가 함께 담긴다', () {
      final result = runPipeline(
        _boxImage(),
        options: const PipelineOptions(thresholds: lenient),
      );

      expect(result.ink.width, 128);
      expect(result.ink.inkCount, greaterThan(0));
      expect(result.quality.regionCount, result.regions.fillableRegionCount);
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart test test/pipeline_test.dart
```

Expected: FAIL — `Undefined name 'runPipeline'`

- [ ] **Step 3: 최소 구현**

`packages/dohan_core/lib/src/pipeline.dart`:

```dart
import 'package:image/image.dart' as img;

import 'binarize.dart';
import 'cleanup.dart';
import 'label_regions.dart';
import 'morphology.dart';
import 'quality_gate.dart';
import 'types.dart';

/// 파이프라인 단계별 조절값.
class PipelineOptions {
  final int binarizeWindow;
  final int binarizeOffset;

  /// 선 끊김 보정 반지름. null이면 선 두께에서 추정한다.
  /// 0을 주면 보정을 건너뛴다 — 테스트에서 누수 기준선을 만들 때만 쓴다.
  final int? closeRadius;

  final int minRegionArea;
  final int neighborSearchRadius;
  final QualityThresholds thresholds;

  const PipelineOptions({
    this.binarizeWindow = 31,
    this.binarizeOffset = 10,
    this.closeRadius,
    this.minRegionArea = 24,
    this.neighborSearchRadius = 3,
    this.thresholds = const QualityThresholds(),
  });
}

/// 파이프라인 산출물.
class PipelineResult {
  /// 보정까지 마친 선 마스크. 선화 렌더링에 쓴다.
  final BinaryMask ink;

  /// 칠할 수 있는 영역이 분리된 인덱스 맵.
  final RegionMap regions;

  final QualityReport quality;

  const PipelineResult({
    required this.ink,
    required this.regions,
    required this.quality,
  });
}

/// 선화 이미지를 도안으로 변환한다.
///
/// 이진화 → 선 끊김 보정 → 연결요소 라벨링 → 영역 정리 → 품질 판정 순으로
/// 진행한다. 빌드 타임 배치 생성과 온디바이스 사진 변환이 이 함수를 공유한다.
PipelineResult runPipeline(
  img.Image source, {
  PipelineOptions options = const PipelineOptions(),
}) {
  final binary = binarize(
    source,
    window: options.binarizeWindow,
    offset: options.binarizeOffset,
  );

  final closed = options.closeRadius == 0
      ? binary
      : closeLines(binary, radius: options.closeRadius);

  final labeled = labelRegions(closed);

  final cleaned = cleanupRegions(
    labeled,
    minArea: options.minRegionArea,
    searchRadius: options.neighborSearchRadius,
  );

  return PipelineResult(
    ink: closed,
    regions: cleaned,
    quality: evaluateQuality(cleaned, thresholds: options.thresholds),
  );
}
```

`packages/dohan_core/lib/dohan_core.dart`에 추가:

```dart
export 'src/pipeline.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test
```

Expected: PASS — 패키지 전체 52개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): 파이프라인 조립과 누수 회귀 테스트"
```

---

### Task 9: 검수 미리보기 렌더러

사람이 도안 품질을 30초 만에 판정할 수 있게 하는 도구다. 영역마다 다른 색을 칠해서 보여주면 잘못 분리된 도안이 눈에 바로 띈다.

**Files:**
- Create: `packages/dohan_core/lib/src/preview.dart`
- Modify: `packages/dohan_core/lib/dohan_core.dart`
- Test: `packages/dohan_core/test/preview_test.dart`

**Interfaces:**
- Consumes: `RegionMap`, ID 상수 (Task 1)
- Produces: `renderRegionPreview(RegionMap, {int seed}) -> img.Image` — 선은 검정, 배경은 연회색, 칠할 수 있는 영역은 각각 다른 색

- [ ] **Step 1: 실패하는 테스트 작성**

`packages/dohan_core/test/preview_test.dart`:

```dart
import 'package:dohan_core/dohan_core.dart';
import 'package:test/test.dart';

void main() {
  group('renderRegionPreview', () {
    test('선은 검정, 배경은 연회색으로 칠한다', () {
      final map = RegionMap.filled(4, 1, kRegionBackground);
      map.set(0, 0, kRegionLine);

      final im = renderRegionPreview(map);

      final line = im.getPixel(0, 0);
      expect([line.r.toInt(), line.g.toInt(), line.b.toInt()], [0, 0, 0]);

      final bg = im.getPixel(1, 0);
      expect(bg.r.toInt(), greaterThan(220));
      expect(bg.r.toInt(), bg.g.toInt());
      expect(bg.g.toInt(), bg.b.toInt());
    });

    test('서로 다른 영역은 서로 다른 색을 받는다', () {
      final map = RegionMap.filled(4, 1, kRegionBackground);
      map.set(0, 0, 2);
      map.set(1, 0, 3);
      map.set(2, 0, 4);

      final im = renderRegionPreview(map);

      final colors = [0, 1, 2].map((x) {
        final p = im.getPixel(x, 0);
        return '${p.r}-${p.g}-${p.b}';
      }).toSet();

      expect(colors.length, 3, reason: '영역 색이 겹치면 검수를 못 한다');
    });

    test('같은 영역은 같은 색을 받는다', () {
      final map = RegionMap.filled(4, 1, kRegionBackground);
      map.set(0, 0, 2);
      map.set(3, 0, 2);

      final im = renderRegionPreview(map);
      final a = im.getPixel(0, 0);
      final b = im.getPixel(3, 0);

      expect(a.r, b.r);
      expect(a.g, b.g);
      expect(a.b, b.b);
    });

    test('같은 seed면 같은 결과가 나온다', () {
      final map = RegionMap.filled(4, 1, kRegionBackground);
      map.set(0, 0, 2);

      final a = renderRegionPreview(map, seed: 7).getPixel(0, 0);
      final b = renderRegionPreview(map, seed: 7).getPixel(0, 0);

      expect(a.r, b.r);
      expect(a.g, b.g);
      expect(a.b, b.b);
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd packages/dohan_core && dart test test/preview_test.dart
```

Expected: FAIL — `Undefined name 'renderRegionPreview'`

- [ ] **Step 3: 최소 구현**

`packages/dohan_core/lib/src/preview.dart`:

```dart
import 'dart:math';

import 'package:image/image.dart' as img;

import 'types.dart';

/// 영역마다 다른 색을 입힌 검수용 이미지를 만든다.
///
/// 선은 검정, 배경은 연회색, 칠할 수 있는 영역은 각각 구분되는 색이다.
/// 영역이 잘못 이어져 있으면 두 곳이 같은 색으로 보이므로 한눈에 알 수 있다.
/// HSV 색상환을 황금각으로 돌며 색을 뽑아 인접 영역끼리 색이 붙지 않게 한다.
img.Image renderRegionPreview(RegionMap map, {int seed = 1}) {
  final im = img.Image(width: map.width, height: map.height, numChannels: 4);
  final palette = <int, List<int>>{};
  final ids = map.fillableRegionIds.toList()..sort();
  final jitter = Random(seed).nextDouble() * 360.0;

  for (var i = 0; i < ids.length; i++) {
    final hue = (jitter + i * 137.508) % 360.0; // 황금각
    palette[ids[i]] = _hsvToRgb(hue, 0.55, 0.95);
  }

  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      final id = map.at(x, y);
      final List<int> rgb;
      if (id == kRegionLine) {
        rgb = const [0, 0, 0];
      } else if (id == kRegionBackground) {
        rgb = const [236, 236, 236];
      } else {
        rgb = palette[id] ?? const [255, 0, 255];
      }
      im.setPixelRgba(x, y, rgb[0], rgb[1], rgb[2], 255);
    }
  }
  return im;
}

List<int> _hsvToRgb(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - ((h / 60.0) % 2 - 1).abs());
  final m = v - c;
  double r, g, b;
  if (h < 60) {
    r = c; g = x; b = 0;
  } else if (h < 120) {
    r = x; g = c; b = 0;
  } else if (h < 180) {
    r = 0; g = c; b = x;
  } else if (h < 240) {
    r = 0; g = x; b = c;
  } else if (h < 300) {
    r = x; g = 0; b = c;
  } else {
    r = c; g = 0; b = x;
  }
  return [
    ((r + m) * 255).round().clamp(0, 255),
    ((g + m) * 255).round().clamp(0, 255),
    ((b + m) * 255).round().clamp(0, 255),
  ];
}
```

`packages/dohan_core/lib/dohan_core.dart`에 추가:

```dart
export 'src/preview.dart';
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd packages/dohan_core && dart test
```

Expected: PASS — 패키지 전체 56개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add packages/dohan_core
git commit -m "feat(dohan_core): 검수용 영역 미리보기 렌더러"
```

---

### Task 10: `dohan_cli` — 배치 생성 CLI

**Files:**
- Create: `tools/dohan_cli/pubspec.yaml`
- Create: `tools/dohan_cli/bin/dohan.dart`
- Test: `tools/dohan_cli/test/cli_test.dart`

**Interfaces:**
- Consumes: `runPipeline`, `PipelineOptions`, `QualityThresholds`, `writeDohanPackage`, `DohanMeta`, `computeRegionCentroids`, `renderRegionPreview` (Task 1~9)
- Produces: `dohan build <입력.png> <출력디렉터리>` · `dohan preview <입력.png> <출력.png>` · 내부 함수 `buildDohan({required File input, required Directory outDir, required String id, required String title, required String category, int canvasSize, int difficulty, List<String> suggestedPalette, QualityThresholds thresholds}) -> Future<QualityReport>` · `writePreview({required File input, required File output}) -> Future<void>`

**캔버스 정규화:** 입력 이미지는 크기가 제각각이므로 `buildDohan`이 스펙 5.3절의 1024×1024 정사각 캔버스에 흰 여백과 함께 맞춰 넣은 뒤 파이프라인에 넣는다. 고밀도 기기용 `lineart@2x.png`는 2048 캔버스에서 이진화·선 보정만 다시 돌려 뽑는다 — 영역 라벨링은 1024에서 한 번만 한다. 두 해상도의 선 경계가 1픽셀 어긋날 수 있지만 선 두께(3px 이상) 안에 묻히므로 채움이 비어 보이지 않는다.

- [ ] **Step 1: 패키지 골격 생성**

```bash
mkdir -p tools/dohan_cli/bin tools/dohan_cli/test
```

`tools/dohan_cli/pubspec.yaml`:

```yaml
name: dohan_cli
description: 선화 이미지를 도안 패키지로 배치 변환하는 CLI.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.5.0

dependencies:
  args: ^2.5.0
  image: ^4.2.0
  dohan_core:
    path: ../../packages/dohan_core

dev_dependencies:
  test: ^1.25.0
  lints: ^4.0.0
```

- [ ] **Step 2: 실패하는 테스트 작성**

`tools/dohan_cli/test/cli_test.dart`:

```dart
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
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd tools/dohan_cli && dart pub get && dart test
```

Expected: FAIL — `Target of URI doesn't exist: '../bin/dohan.dart'`

- [ ] **Step 4: 최소 구현**

`tools/dohan_cli/bin/dohan.dart`:

```dart
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

int _requireInt(String name, String raw) {
  final value = int.tryParse(raw);
  if (value == null) {
    throw FormatException('$name 값은 정수여야 합니다: "$raw"');
  }
  return value;
}

/// 파일 이름에서 마지막 확장자만 떼어 기본 ID 를 만든다.
///
/// 첫 번째 점에서 자르면 `cat.v2.final.png` 가 `cat` 이 되어, 버전이 다른
/// 파일들이 같은 ID 로 뭉개진다.
String defaultIdFor(File input) {
  final name = input.uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
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
    final id = (argResults!['id'] as String?) ?? defaultIdFor(input);
    final title = (argResults!['title'] as String?) ?? id;

    final report = await buildDohan(
      input: input,
      outDir: outDir,
      id: id,
      title: title,
      category: argResults!['category'] as String,
      canvasSize:
          _requireInt('--canvas-size', argResults!['canvas-size'] as String),
      difficulty:
          _requireInt('--difficulty', argResults!['difficulty'] as String),
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

/// 인자를 파싱해 명령을 실행하고 종료 코드를 돌려준다.
///
/// main 과 테스트가 이 함수를 공유한다. 예외가 그대로 빠져나가면 종료 코드가
/// 255 가 되고 영어 스택 트레이스가 찍혀, 배치 스크립트에서 원인을 알 수 없다.
Future<int> runDohan(List<String> args) async {
  final runner = CommandRunner<int>('dohan', '도안 에셋 파이프라인 도구')
    ..addCommand(_BuildCommand())
    ..addCommand(_PreviewCommand());
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    stderr.writeln(e.usage);
    return 64;
  } on FormatException catch (e) {
    stderr.writeln('입력을 처리할 수 없습니다: ${e.message}');
    return 65;
  } catch (e) {
    stderr.writeln('실패했습니다: $e');
    return 70;
  }
}

Future<void> main(List<String> args) async {
  exitCode = await runDohan(args);
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd tools/dohan_cli && dart test
```

Expected: PASS — 11개 테스트 통과

- [ ] **Step 6: CLI 수동 확인**

```bash
cd tools/dohan_cli && dart run bin/dohan.dart --help
```

Expected: `build`와 `preview` 두 서브커맨드가 목록에 보인다.

- [ ] **Step 7: 커밋**

```bash
git add tools/dohan_cli
git commit -m "feat(dohan_cli): 도안 배치 생성과 검수 미리보기 CLI"
```

---

### Task 11: `dohan_gen` — 프롬프트 템플릿과 이미지 수급 도구

**Files:**
- Create: `tools/dohan_gen/prompts.py`
- Create: `tools/dohan_gen/providers.py`
- Create: `tools/dohan_gen/generate.py`
- Create: `tools/dohan_gen/README.md`
- Test: `tools/dohan_gen/test_prompts.py`

**Interfaces:**
- Consumes: 없음 (Dart 코드와 독립)
- Produces: `build_prompt(category, subject) -> str` · `CATEGORIES` · `SUBJECTS` · `Provider` 추상 클래스 (`fetch(prompt, index) -> bytes`) · `FilesystemProvider` · `generate.py` CLI

**결정이 필요한 항목:** 어떤 이미지 생성 서비스를 쓸지는 아직 정해지지 않았다. 이 태스크는 **provider 인터페이스와, API 키 없이 지금 바로 동작하는 `FilesystemProvider`**(수동으로 내려받은 이미지를 읽어 쓰는 구현)를 만든다. 서비스를 고른 뒤 provider 하나를 추가하면 된다. 어떤 서비스를 쓰든 **생성물의 상업적 이용 조건을 먼저 확인해야 한다** — 내장 도안 50장이 앱의 판매 가능성에 직접 걸린다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tools/dohan_gen/test_prompts.py`:

```python
import unittest

from prompts import CATEGORIES, SUBJECTS, build_prompt


class BuildPromptTest(unittest.TestCase):
    def test_네_카테고리가_정의되어_있다(self):
        self.assertEqual(
            set(CATEGORIES), {"animal", "car", "dinosaur", "character"}
        )

    def test_모든_카테고리에_소재가_있다(self):
        for category in CATEGORIES:
            self.assertTrue(SUBJECTS[category], f"{category}에 소재가 없다")

    def test_프롬프트에_소재와_필수_제약이_들어간다(self):
        prompt = build_prompt("dinosaur", "triceratops")

        self.assertIn("triceratops", prompt)
        self.assertIn("closed shapes", prompt)
        self.assertIn("no shading", prompt)
        self.assertIn("white background", prompt)

    def test_모르는_카테고리는_거부한다(self):
        with self.assertRaises(ValueError):
            build_prompt("spaceship", "rocket")

    def test_캐릭터는_기존_IP를_배제하는_문구를_포함한다(self):
        prompt = build_prompt("character", "friendly robot")

        self.assertIn("original", prompt.lower())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd tools/dohan_gen && python -m unittest test_prompts -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'prompts'`

- [ ] **Step 3: 최소 구현**

`tools/dohan_gen/prompts.py`:

```python
"""카테고리별 선화 생성 프롬프트."""

CATEGORIES = ("animal", "car", "dinosaur", "character")

SUBJECTS = {
    "animal": [
        "sitting cat", "puppy with floppy ears", "elephant with raised trunk",
        "rabbit eating a carrot", "penguin standing", "lion with a mane",
        "giraffe reaching for leaves", "turtle with a patterned shell",
    ],
    "car": [
        "fire truck", "school bus", "excavator", "police car",
        "race car", "garbage truck", "tractor", "ambulance",
    ],
    "dinosaur": [
        "triceratops", "stegosaurus", "tyrannosaurus rex", "brachiosaurus",
        "pterodactyl in flight", "ankylosaurus", "baby dinosaur hatching",
    ],
    "character": [
        "friendly robot", "smiling cloud with a face", "star wearing a hat",
        "little astronaut", "cheerful sun", "sleepy moon",
    ],
}

_BASE = (
    "thick black outline coloring book page for toddlers, {subject}, "
    "closed shapes with every outline fully connected, no shading, "
    "no gradients, no texture, no hatching, pure white background, "
    "bold uniform line weight, centered composition, "
    "large simple fillable areas"
)

# 캐릭터는 기존 IP를 쓰지 않는다. 생성 단계에서 못을 박아 둔다.
_CHARACTER_SUFFIX = (
    ", completely original character design, "
    "not resembling any existing franchise or branded character"
)


def build_prompt(category: str, subject: str) -> str:
    """도안 한 장을 만들 프롬프트를 조립한다."""
    if category not in CATEGORIES:
        raise ValueError(
            f"알 수 없는 카테고리: {category!r}. "
            f"가능한 값: {', '.join(CATEGORIES)}"
        )
    prompt = _BASE.format(subject=subject)
    if category == "character":
        prompt += _CHARACTER_SUFFIX
    return prompt
```

`tools/dohan_gen/providers.py`:

```python
"""이미지 수급 provider.

이미지 생성 서비스를 아직 고르지 않았으므로, 지금은 수동으로 내려받은
파일을 읽어 쓰는 FilesystemProvider만 제공한다. 서비스를 정하면 Provider를
상속한 클래스를 하나 추가하면 된다 — generate.py는 바뀌지 않는다.
"""

from abc import ABC, abstractmethod
from pathlib import Path


class Provider(ABC):
    """프롬프트 하나에 대해 선화 이미지 바이트를 돌려준다."""

    @abstractmethod
    def fetch(self, prompt: str, index: int) -> bytes:
        ...


class FilesystemProvider(Provider):
    """미리 준비한 이미지를 순서대로 읽는다.

    API 키 없이 파이프라인 전체를 돌려볼 수 있게 하는 구현이다.
    `source_dir` 안의 png/jpg 파일을 이름순으로 하나씩 내준다.
    """

    def __init__(self, source_dir: Path):
        self.files = sorted(
            p for p in source_dir.iterdir()
            if p.suffix.lower() in (".png", ".jpg", ".jpeg")
        )
        if not self.files:
            raise FileNotFoundError(f"이미지가 없습니다: {source_dir}")

    def fetch(self, prompt: str, index: int) -> bytes:
        return self.files[index % len(self.files)].read_bytes()
```

`tools/dohan_gen/generate.py`:

```python
"""선화 원본을 모아 dohan_cli가 읽을 수 있는 폴더로 떨군다.

사용 예:
    python generate.py --category dinosaur --count 4 \
        --provider filesystem --source ./raw --out ./lineart
"""

import argparse
import json
from pathlib import Path

from prompts import CATEGORIES, SUBJECTS, build_prompt
from providers import FilesystemProvider


def main() -> int:
    parser = argparse.ArgumentParser(description="도안 선화 원본 생성")
    parser.add_argument("--category", required=True, choices=CATEGORIES)
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--provider", default="filesystem",
                        choices=["filesystem"])
    parser.add_argument("--source", type=Path,
                        help="filesystem provider가 읽을 원본 디렉터리")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    if args.provider == "filesystem":
        if args.source is None:
            parser.error("--provider filesystem 에는 --source 가 필요합니다")
        provider = FilesystemProvider(args.source)

    args.out.mkdir(parents=True, exist_ok=True)
    subjects = SUBJECTS[args.category]
    manifest = []

    for i in range(args.count):
        subject = subjects[i % len(subjects)]
        prompt = build_prompt(args.category, subject)
        slug = subject.replace(" ", "-")
        name = f"{args.category}-{slug}-{i:02d}.png"
        (args.out / name).write_bytes(provider.fetch(prompt, i))
        manifest.append({
            "file": name,
            "category": args.category,
            "subject": subject,
            "prompt": prompt,
        })
        print(f"저장: {name}")

    (args.out / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"완료: {len(manifest)}장 → {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

`tools/dohan_gen/README.md`:

```markdown
# dohan_gen

도안 선화 원본을 모아 `dohan_cli`에 넘길 폴더를 만든다.

## 흐름

```
generate.py → lineart/*.png → dohan build → 도안 패키지
```

## 지금 할 수 있는 것

이미지 생성 서비스를 아직 고르지 않았으므로, 직접 준비한 선화 이미지를
`FilesystemProvider`로 읽어 쓴다.

```bash
python generate.py --category dinosaur --count 4 \
    --provider filesystem --source ./raw --out ./lineart
```

`manifest.json`에 각 파일의 프롬프트가 기록되므로, 나중에 같은 프롬프트로
재생성할 수 있다.

## 서비스를 고른 뒤

`providers.py`에 `Provider`를 상속한 클래스를 하나 추가하고 `generate.py`의
`--provider` 선택지에 넣는다. 그 밖의 코드는 바뀌지 않는다.

**반드시 먼저 확인할 것:** 생성물의 상업적 이용 조건. 내장 도안이 앱의
판매 가능성에 직접 걸린다.

## 프롬프트 규칙

`prompts.py`의 기본 템플릿은 다음을 강제한다.

- 굵고 균일한 검정 외곽선
- 모든 외곽선이 닫혀 있을 것 (끊긴 선은 색이 새는 원인)
- 명암·그라데이션·텍스처·해칭 없음
- 순백 배경
- 크고 단순한 칠할 영역

`character` 카테고리에는 기존 IP를 배제하는 문구가 자동으로 붙는다.
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd tools/dohan_gen && python -m unittest test_prompts -v
```

Expected: PASS — 5개 테스트 통과

- [ ] **Step 5: 커밋**

```bash
git add tools/dohan_gen
git commit -m "feat(dohan_gen): 프롬프트 템플릿과 이미지 수급 provider"
```

---

## 완료 조건

계획 1이 끝나면 다음이 동작한다.

```bash
# 선화 이미지 하나를 도안으로 변환
cd tools/dohan_cli
dart run bin/dohan.dart build ../../raw/dino.png ../../assets/dohans/dino-01 \
    --category dinosaur --title "삼각 공룡"

# 영역 분리가 제대로 됐는지 눈으로 확인
dart run bin/dohan.dart preview ../../raw/dino.png /tmp/check.png
```

전체 테스트:

```bash
cd packages/dohan_core && dart test
cd ../../tools/dohan_cli && dart test
cd ../dohan_gen && python -m unittest discover
```

## 계획 1 완료 후 할 일

1. 실제 선화 10장을 파이프라인에 통과시키고 `minTapDiameterPx`, `minRegionArea`, `closeRadius` 기본값을 재측정한다
2. 측정 결과로 스펙 6.2절의 터치 타겟 기준을 갱신한다
3. 이미지 생성 서비스를 고르고 상업적 이용 조건을 확인한다
4. 계획 2(색칠 엔진 + 앱 셸) 작성으로 넘어간다
