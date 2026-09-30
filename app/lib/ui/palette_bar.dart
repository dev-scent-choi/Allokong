import 'package:flutter/material.dart';

import 'palette_shades.dart';

/// 색 하나를 고르는 동그란 버튼.
///
/// 터치 타겟을 64dp 로 잡는다 — 스펙 10.3 절의 최소값이고, 아이 손가락은
/// 어른보다 부정확하다.
class ColorSwatchButton extends StatelessWidget {
  static const double size = 64;

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              // 고르지 않은 색도 테두리를 그린다. 투명하게 두면 흰색 크레용이
              // 배경(#FCFCF8)에 묻혀 아예 보이지 않는다 — 대비 1.06:1.
              // #757D75 는 #FCFCF8 대비 4.13:1, #F5F5F5(흰색 스와치 자체) 대비
              // 3.89:1 로 둘 다 비문자 UI 요소 기준인 3:1 을 넘긴다(계산 확인,
              // 리뷰가 제안한 #8C948D 는 흰색 스와치 대비 2.86:1 로 기준 미달).
              border: Border.all(
                color: selected
                    ? const Color(0xFF202923)
                    : const Color(0xFF757D75),
                width: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 색 고르는 줄.
///
/// 색이 아니라 **자리(index)** 를 주고받는다. 명도 버튼을 누르면 여덟 색이
/// 통째로 바뀌는데, 그때도 아이가 고른 자리는 그대로여야 하기 때문이다.
class PaletteBar extends StatelessWidget {
  final Shade shade;
  final int selectedIndex;
  final ValueChanged<int> onPickIndex;

  const PaletteBar({
    super.key,
    required this.shade,
    required this.selectedIndex,
    required this.onPickIndex,
  });

  @override
  Widget build(BuildContext context) {
    final colors = paletteShades[shade]!;
    // Wrap 이지 가로 ListView 가 아니다. 64dp 여덟 개는 512dp 라 좁은 기기에서
    // 마지막 두 색이 화면 밖으로 밀려나고, 글을 못 읽는 아이는 줄이 옆으로
    // 스크롤된다는 것을 알아낼 방법이 없다 — 보이지 않는 색은 없는 색이다.
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < colors.length; i++)
          ColorSwatchButton(
            color: colors[i],
            selected: i == selectedIndex,
            onTap: () => onPickIndex(i),
          ),
      ],
    );
  }
}
