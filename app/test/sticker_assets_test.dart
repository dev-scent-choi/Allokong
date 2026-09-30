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
