import 'package:flutter/material.dart';

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
class PaletteBar extends StatelessWidget {
  /// 스펙 9장의 유아 기본 팔레트 8색.
  static const toddlerPalette = <Color>[
    Color(0xFFEF7586), // 분홍
    Color(0xFFF1BD45), // 노랑
    Color(0xFFEF8A45), // 주황
    Color(0xFF6CAEE0), // 파랑
    Color(0xFF63B98B), // 초록
    Color(0xFF9E82CF), // 보라
    Color(0xFF795548), // 갈색
    Color(0xFFF5F5F5), // 흰색
  ];

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onPick;

  const PaletteBar({
    super.key,
    required this.colors,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap 이지 가로 ListView 가 아니다. 64dp 여덟 개는 512dp 라 좁은 기기에서
    // 마지막 두 색(갈색·흰색)이 화면 밖으로 밀려난다. 글을 못 읽는 아이는
    // 줄이 옆으로 스크롤된다는 것을 알아낼 방법이 없다 — 보이지 않는 색은
    // 없는 색이다. 줄바꿈하면 좁은 화면에서 두 줄이 되고 여덟 색이 다 보인다.
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final c in colors)
          ColorSwatchButton(
            color: c,
            selected: c.toARGB32() == selected.toARGB32(),
            onTap: () => onPick(c),
          ),
      ],
    );
  }
}
