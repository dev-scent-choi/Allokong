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
