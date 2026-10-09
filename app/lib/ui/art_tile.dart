import 'package:flutter/material.dart';

/// 격자 한 칸의 최소 변. 상위 스펙 10.3 의 터치 타겟이다.
const double kArtTileMinSize = 64;

/// 놀기와 모아보기가 함께 쓰는 격자 칸의 **틀**.
///
/// 담는 것은 서로 다르다 — 놀기는 도안의 선화를, 모아보기는 작품의
/// 썸네일(없으면 선화)을 보여준다. 하나의 "도안 타일"로 합치면 둘 중
/// 하나에 안 맞는 인자가 생기므로, 공통인 정사각 비율·모서리·터치 영역만
/// 여기서 맡고 그림은 [child] 로 받는다.
class ArtTile extends StatelessWidget {
  /// 접근성 도구와 테스트가 칸을 구분할 이름.
  final String label;

  final Widget child;
  final VoidCallback onTap;

  const ArtTile({
    super.key,
    required this.label,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        // 썸네일이 아직 안 읽혔으면 칸 속이 비어 있다. opaque 가 없으면
        // 그 칸은 입력을 흘려보내 "눌리지 않는 그림"이 된다.
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kArtTileMinSize,
            minHeight: kArtTileMinSize,
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD8DCD8), width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
