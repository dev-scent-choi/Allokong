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
