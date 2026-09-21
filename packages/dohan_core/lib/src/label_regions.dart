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
