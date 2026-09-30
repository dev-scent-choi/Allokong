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
