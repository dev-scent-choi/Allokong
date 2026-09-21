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
