import 'dart:collection';
import 'dart:typed_data';

import 'types.dart';

/// 칠할 수 있는 픽셀마다 자기 영역 경계까지의 체비셰프 거리를 구한다.
///
/// 영역이 아닌 픽셀(선·배경)과 아직 닿지 않은 픽셀은 -1 이다. 경계는 자기와
/// 다른 ID 를 가진 8방 이웃이 있거나 캔버스 가장자리인 픽셀이며, 거리 0 에서
/// 시작하는 다중 시작점 BFS 로 안쪽으로 퍼진다. 전파는 같은 ID 안에서만
/// 일어나므로 배열 하나로 모든 영역의 거리장을 동시에 구할 수 있다.
Int32List chebyshevDistanceField(RegionMap map) {
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

  return dist;
}

/// 영역마다 내접원이 가장 큰 지점을 구한다.
///
/// 무게중심이 아니라 이 지점을 쓰는 이유는, 고리나 초승달처럼 오목한 영역에서
/// 무게중심이 영역 밖(가운데 구멍)에 떨어지기 때문이다. 거리장의 최댓값 위치는
/// 정의상 항상 자기 영역 안에 있다. 같은 값이 여럿이면 래스터 순서상 처음
/// 나온 것을 쓰므로 결과는 결정적이다.
///
/// 반환값은 영역 ID → [x, y].
Map<int, List<int>> computeRegionAnchors(RegionMap map) {
  final w = map.width;
  final h = map.height;
  final dist = chebyshevDistanceField(map);

  final bestDist = <int, int>{};
  final bestPoint = <int, List<int>>{};
  for (var i = 0; i < w * h; i++) {
    final id = map.ids[i];
    if (id < kRegionFirstFillable) continue;
    final d = dist[i];
    if (d > (bestDist[id] ?? -1)) {
      bestDist[id] = d;
      bestPoint[id] = [i % w, i ~/ w];
    }
  }
  return bestPoint;
}

/// 칠할 수 있는 영역들의 최대 내접원 지름 중 가장 작은 값.
///
/// 체비셰프 거리라 내접 "정사각형"이지만 터치 가능성 판정에는 충분하다.
/// 칠할 수 있는 영역이 없으면 0.
int smallestInscribedDiameter(RegionMap map) {
  final w = map.width;
  final h = map.height;
  final dist = chebyshevDistanceField(map);

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
