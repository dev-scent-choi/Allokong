import 'package:flutter/material.dart';

/// 셸의 탭 다섯.
///
/// `create` 와 `rank` 는 계획 5·6 의 자리다. 지금 칸을 만들어 두는 것은
/// 상위 스펙 10.1 이 `만들기` 를 중앙의 큰 더하기 버튼으로 분리하라고 해서
/// 그 버튼이 위젯의 구조 자체를 바꾸기 때문이다 — 나중에 끼워 넣으면
/// 64dp 기하를 다시 재야 한다.
enum ShellTab { play, gallery, create, rank, me }

/// 내비 한 줄의 높이. 상위 스펙 10.3 의 최소 터치 타겟이다.
const double kNavHeight = 64;

const _slots = <(ShellTab, IconData, String)>[
  (ShellTab.play, Icons.palette, '놀기'),
  (ShellTab.gallery, Icons.photo_library, '모아보기'),
  (ShellTab.create, Icons.add, '만들기'),
  (ShellTab.rank, Icons.emoji_events, '랭크'),
  (ShellTab.me, Icons.person, '내 정보'),
];

const _green = Color(0xFF246B4B);
const _grey = Color(0xFF6B736C);

/// 고정 하단 내비게이션.
///
/// 색칠 화면에는 올라가지 않는다(설계 스펙 2.1) — 320x640 에서 내비를
/// 넣으면 캔버스가 350 에서 286dp 로 줄어 본문의 절반 아래가 된다.
class BottomNav extends StatelessWidget {
  final ShellTab selected;
  final ValueChanged<ShellTab> onSelect;

  const BottomNav({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      // bottomNavigationBar 는 아래쪽 인셋을 스스로 처리하지 않는다.
      // 감싸지 않으면 64dp 중 아래쪽이 제스처 바 밑으로 들어가 실제 히트
      // 영역이 줄고, 아이가 그 부분을 누르면 탭 대신 홈 제스처가 먹는다.
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kNavHeight,
          child: Row(
            children: [
              // 320dp 에서 Expanded 다섯은 정확히 64dp 씩이다. 더 좁은
              // 화면에서는 넘치는 대신 줄어든다 — 아이에게 칸이 사라지는
              // 것보다 작아지는 편이 낫다.
              for (final (tab, icon, label) in _slots)
                Expanded(
                  child: NavSlot(
                    // 라벨로 찾으면 모호하다 — `내 정보` 는 설정 화면의
                    // 제목이기도 해서, 그 탭에 있을 때 둘이 잡힌다.
                    key: ValueKey('nav-${tab.name}'),
                    tab: tab,
                    icon: icon,
                    label: label,
                    selected: tab == selected,
                    onTap: () => onSelect(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 내비 칸 하나.
///
/// 공개 타입인 것은 테스트가 "다섯 칸이 64dp 를 지키는지"를 직접 재기
/// 위해서다 — 320dp 에 여유가 0 이라 그 테스트가 꼭 필요하다.
class NavSlot extends StatelessWidget {
  final ShellTab tab;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const NavSlot({
    super.key,
    required this.tab,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // `만들기` 는 상위 스펙 10.1 이 "중앙의 큰 더하기 버튼으로 분리"하라고
    // 한 자리다. 색이 아니라 모양으로 구분한다.
    final isCreate = tab == ShellTab.create;
    final tint = selected ? _green : _grey;

    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: kNavHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isCreate)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(icon, size: 22, color: Colors.white),
                  ),
                )
              else
                Icon(icon, size: 26, color: tint),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: isCreate ? _green : tint,
                  // 고른 칸을 색만으로 알리지 않는다.
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
