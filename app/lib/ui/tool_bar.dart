import 'package:flutter/material.dart';

import '../coloring/coloring_controller.dart' show ToolKind;

/// 도구 칸 하나의 크기. 스펙 10.3 의 최소 터치 타겟이다.
const double kToolSize = 64;

/// 도구 하나를 고르는 칸.
class ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: kToolSize,
          height: kToolSize,
          child: Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFE6EFE9) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF246B4B)
                      : const Color(0xFFD8DCD8),
                  width: 3,
                ),
              ),
              child: Icon(icon,
                  size: 28,
                  color: selected
                      ? const Color(0xFF246B4B)
                      : const Color(0xFF6B736C)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 도구 다섯 개. 320dp 화면에서 64dp 다섯 개가 한 줄에 정확히 들어간다.
class ToolBar extends StatelessWidget {
  final ToolKind selected;
  final ValueChanged<ToolKind> onSelect;

  const ToolBar({super.key, required this.selected, required this.onSelect});

  static const _tools = <(ToolKind, IconData, String)>[
    (ToolKind.bucket, Icons.format_color_fill, '색 채우기'),
    (ToolKind.crayon, Icons.edit, '크레용'),
    (ToolKind.brush, Icons.brush, '붓'),
    (ToolKind.eraser, Icons.cleaning_services, '지우개'),
    (ToolKind.sticker, Icons.auto_awesome, '스티커'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kToolSize,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (kind, icon, label) in _tools)
            ToolButton(
              icon: icon,
              label: label,
              selected: kind == selected,
              onTap: () => onSelect(kind),
            ),
        ],
      ),
    );
  }
}
