import 'package:flutter/material.dart';

import '../gallery/artwork_repository.dart';
import 'settings.dart';

/// 보호자가 보는 화면. 이 앱에서 **유일하게 어른이 읽는 자리**라 글을 써도
/// 된다.
///
/// 닉네임·공개 범위·음소거는 넣지 않는다. 랭크와 공유와 효과음이 아직
/// 없어서, 지금 만들면 아무것도 하지 않는 스위치가 된다(설계 스펙 1절).
class SettingsScreen extends StatefulWidget {
  final SettingsStore store;
  final ArtworkRepository repository;

  /// 셸이 쥐고 있는 현재 값.
  final AgeMode ageMode;

  /// 아이가 다음에 색칠을 열 때 이 값이 쓰인다.
  final ValueChanged<AgeMode> onAgeModeChanged;

  /// 작품을 다 지운 뒤. 모아보기와 놀기가 다시 읽어야 한다.
  final VoidCallback? onDataCleared;

  const SettingsScreen({
    super.key,
    required this.store,
    required this.repository,
    required this.ageMode,
    required this.onAgeModeChanged,
    this.onDataCleared,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _pick(AgeMode mode) async {
    if (mode == widget.ageMode) return;
    widget.onAgeModeChanged(mode);
    await widget.store.save(Settings(ageMode: mode));
  }

  /// 되돌릴 수 없으므로 두 단계를 거친다. 작품별 삭제가 없으므로 정리
  /// 수단은 이것뿐이고, 그만큼 실수로 눌리면 안 된다.
  Future<void> _clearData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모든 그림을 지울까요?'),
        content: const Text(
          '아이가 그린 그림이 모두 사라지고 되돌릴 수 없습니다.\n'
          '연령대 설정은 그대로 남습니다.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('clear-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            key: const ValueKey('clear-confirm'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFC6172F)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await widget.repository.deleteAll();
    widget.onDataCleared?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('내 정보', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        Text('연령대', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          '유아는 색 채우기 하나로 단순하게, 아동은 크레용·붓·지우개·'
          '스티커까지 모두 씁니다.',
          style: TextStyle(color: Color(0xFF6B736C)),
        ),
        const SizedBox(height: 12),
        _AgeChoice(
          buttonKey: const ValueKey('age-toddler'),
          title: '유아 (3~5세)',
          selected: widget.ageMode == AgeMode.toddler,
          onTap: () => _pick(AgeMode.toddler),
        ),
        const SizedBox(height: 8),
        _AgeChoice(
          buttonKey: const ValueKey('age-child'),
          title: '아동 (6~9세)',
          selected: widget.ageMode == AgeMode.child,
          onTap: () => _pick(AgeMode.child),
        ),
        const SizedBox(height: 32),
        Text('데이터', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          '그림은 이 기기에만 저장됩니다. 하나씩 지우는 기능은 없습니다 — '
          '아이가 실수로 지우는 일을 막기 위해서입니다.',
          style: TextStyle(color: Color(0xFF6B736C)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('clear-data'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            foregroundColor: const Color(0xFFC6172F),
          ),
          onPressed: _clearData,
          child: const Text('모든 그림 지우기'),
        ),
      ],
    );
  }
}

class _AgeChoice extends StatelessWidget {
  final Key buttonKey;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _AgeChoice({
    required this.buttonKey,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: buttonKey,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        backgroundColor:
            selected ? const Color(0xFFE6EFE9) : Colors.transparent,
        side: BorderSide(
          color: selected ? const Color(0xFF246B4B) : const Color(0xFFD8DCD8),
          width: 3,
        ),
        foregroundColor: const Color(0xFF1C1F1D),
      ),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? const Color(0xFF246B4B) : const Color(0xFF6B736C),
          ),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}
