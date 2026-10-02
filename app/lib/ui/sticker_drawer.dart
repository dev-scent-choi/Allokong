import 'package:flutter/material.dart';

import '../coloring/sticker_state.dart';
import 'tool_bar.dart' show kToolSize;

/// 스티커 하나를 고르는 칸.
class StickerButton extends StatelessWidget {
  final String stickerId;
  final VoidCallback onTap;

  const StickerButton({
    super.key,
    required this.stickerId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '스티커 $stickerId',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: kToolSize,
          height: kToolSize,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset('assets/stickers/$stickerId.png'),
          ),
        ),
      ),
    );
  }
}

/// 스티커 서랍.
///
/// 열 개뿐인 것은 화면 때문이다 — 320dp 에서 64dp 칸이 한 줄에 다섯이고
/// 상황별 영역이 두 줄이다. 스크롤되는 줄은 글을 못 읽는 아이에게 보이지
/// 않는 것과 같다.
class StickerDrawer extends StatelessWidget {
  final ValueChanged<String> onPick;

  const StickerDrawer({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final id in kStickerIds)
          StickerButton(stickerId: id, onTap: () => onPick(id)),
      ],
    );
  }
}
