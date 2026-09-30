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
