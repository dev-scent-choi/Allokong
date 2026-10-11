import 'package:flutter/material.dart';

import '../coloring/coloring_route.dart';
import '../core/dohan_source.dart';
import '../gallery/artwork_repository.dart';
import '../gallery/gallery_screen.dart';
import '../play/play_screen.dart';
import '../settings/settings.dart';
import '../settings/settings_screen.dart';
import 'bottom_nav.dart';
import 'placeholder_screen.dart';

/// 탭 다섯을 묶는 껍데기.
///
/// 색칠은 탭이 아니라 이 위에 띄운다(설계 스펙 2.1). 그래서 색칠 중에는
/// 내비가 보이지 않고, "다른 탭을 누르면 확인한다"는 요구가 함께 사라진다 —
/// 누를 탭이 없다.
class ShellScreen extends StatefulWidget {
  final DohanSource source;
  final ArtworkRepository repository;
  final SettingsStore settingsStore;
  final AgeMode initialAgeMode;

  const ShellScreen({
    super.key,
    required this.source,
    required this.repository,
    required this.settingsStore,
    required this.initialAgeMode,
  });

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  ShellTab _tab = ShellTab.play;
  late AgeMode _ageMode = widget.initialAgeMode;

  /// 탭들에게 "다시 읽어라"를 알리는 숫자.
  ///
  /// 탭은 `IndexedStack` 안에 살아 있어서(스크롤 위치를 지키려는 것이다)
  /// 스스로 다시 지어지지 않는다. 색칠에서 돌아오거나 데이터를 지웠을 때
  /// 이 값을 올려 주지 않으면 놀기에서 그린 그림이 모아보기에 영영
  /// 나타나지 않는다.
  int _refresh = 0;

  Future<void> _openColoring({
    required String dohanId,
    required String artworkId,
  }) async {
    await openColoring(
      context,
      source: widget.source,
      repository: widget.repository,
      ageMode: _ageMode,
      dohanId: dohanId,
      artworkId: artworkId,
    );
    if (mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFCF8),
      // IndexedStack 은 다섯을 모두 살려 둔다. 탭을 오갈 때 스크롤 위치가
      // 유지되는 것이 이것 때문이다 — 아이가 모아보기를 보다 돌아왔을 때
      // 놀기가 처음으로 튀면 안 된다.
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: ShellTab.values.indexOf(_tab),
          children: [
            PlayScreen(
              source: widget.source,
              repository: widget.repository,
              onOpen: _openColoring,
              refreshToken: _refresh,
            ),
            GalleryScreen(
              repository: widget.repository,
              onOpen: _openColoring,
              refreshToken: _refresh,
            ),
            const PlaceholderScreen(
              icon: Icons.add_a_photo_outlined,
              title: '곧 만들 수 있어요',
              message: '그린 그림을 사진으로 찍어 도안으로 만듭니다',
            ),
            const PlaceholderScreen(
              icon: Icons.emoji_events_outlined,
              title: '곧 열려요',
              message: '색칠하고 만든 만큼 모으는 자리입니다',
            ),
            SettingsScreen(
              store: widget.settingsStore,
              repository: widget.repository,
              ageMode: _ageMode,
              onAgeModeChanged: (mode) => setState(() => _ageMode = mode),
              onDataCleared: () => setState(() => _refresh++),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNav(
        selected: _tab,
        onSelect: (tab) => setState(() => _tab = tab),
      ),
    );
  }
}
