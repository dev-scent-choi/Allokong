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
