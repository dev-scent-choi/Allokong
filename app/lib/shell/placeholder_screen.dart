import 'package:flutter/material.dart';

/// 아직 만들지 않은 탭. `만들기`(계획 5)와 `랭크`(계획 6)가 쓴다.
///
/// 출시 전에만 보이는 화면이다. 칸을 지금 만들어 두는 이유는
/// `bottom_nav.dart` 의 [ShellTab] 주석에 있다.
class PlaceholderScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const PlaceholderScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 96, color: const Color(0xFFB7BFB8)),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(color: Color(0xFF6B736C))),
        ],
      ),
    );
  }
}
