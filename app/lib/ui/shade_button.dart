import 'package:flutter/material.dart';

import 'palette_shades.dart';
import 'tool_bar.dart' show kToolSize;

/// 팔레트 명도를 한 바퀴 돌리는 버튼.
///
/// 앱바에 둔다. 24색을 다 펼치면 320dp 화면에서 팔레트가 본문의 59% 를 먹는다 —
/// 설계 문서 3.2절. 대신 여덟 색은 그대로 두고 이 버튼이 명도를 바꾼다.
class ShadeButton extends StatelessWidget {
  final Shade shade;
  final VoidCallback onCycle;

  const ShadeButton({super.key, required this.shade, required this.onCycle});

  static const _labels = {
    Shade.light: '연하게',
    Shade.base: '기본',
    Shade.dark: '진하게',
  };

  @override
  Widget build(BuildContext context) {
    // 지금 명도의 분홍을 보여 준다. 무엇이 바뀌는지를 글자 대신 색으로 알린다.
    final swatch = paletteShades[shade]!.first;
    return Semantics(
      label: '색 진하기 — ${_labels[shade]}',
      button: true,
      child: GestureDetector(
        onTap: onCycle,
        child: SizedBox(
          width: kToolSize,
          height: kToolSize,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF757D75), width: 3),
              ),
              child: Icon(
                switch (shade) {
                  Shade.light => Icons.brightness_low,
                  Shade.base => Icons.brightness_medium,
                  Shade.dark => Icons.brightness_high,
                },
                size: 18,
                color: const Color(0xFF202923),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
