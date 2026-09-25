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
              border: Border.all(
                color: selected ? const Color(0xFF202923) : Colors.transparent,
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
    return SizedBox(
      height: ColorSwatchButton.size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in colors)
            ColorSwatchButton(
              color: c,
              selected: c.toARGB32() == selected.toARGB32(),
              onTap: () => onPick(c),
            ),
        ],
      ),
    );
  }
}
