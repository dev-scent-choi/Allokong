import 'dart:async';

import 'package:flutter/material.dart';

import '../core/dohan_source.dart';
import '../gallery/artwork_repository.dart';
import '../gallery/autosave.dart';
import '../settings/settings.dart';
import '../ui/coloring_screen.dart';
import 'coloring_controller.dart';

/// 같은 밀리초 안에 두 번 만들어도 겹치지 않게 하는 카운터.
int _seq = 0;

/// 새 작품의 id. 도안 하나를 여러 번 칠할 수 있으므로 매번 새로 만든다.
///
/// 밀리초만 쓰면 아이가 도안을 빠르게 두 번 누를 때 같은 id 가 나와 두
/// 작품이 한 폴더를 공유한다 — 계획 3 의 스티커 instanceId 와 같은 함정이다.
String newArtworkId(String dohanId) =>
    '$dohanId-${DateTime.now().millisecondsSinceEpoch}-${_seq++}';

/// 셸이 탭에게 건네는 "색칠을 열어라". 아이가 나올 때까지 기다린다.
///
/// 탭은 `source`·`repository`·`ageMode` 를 몰라도 된다 — 그것들은 셸이
/// 쥐고 있고, 셸은 색칠이 끝나면 탭들에게 다시 읽으라고 알린다.
typedef OpenColoring = Future<void> Function({
  required String dohanId,
  required String artworkId,
});

/// 색칠 화면을 셸 위에 띄운다. 아이가 나올 때까지 기다린다.
///
/// 내비는 함께 올라가지 않는다(설계 스펙 2.1) — 320×640 에서 내비를 넣으면
/// 캔버스가 350 에서 286dp 로 줄어 본문의 절반 아래가 된다.
Future<void> openColoring(
  BuildContext context, {
  required DohanSource source,
  required ArtworkRepository repository,
  required AgeMode ageMode,
  required String dohanId,
  required String artworkId,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ColoringSession(
        source: source,
        repository: repository,
        ageMode: ageMode,
        dohanId: dohanId,
        artworkId: artworkId,
      ),
    ),
  );
}

/// 색칠 세션 하나의 생애를 쥔다.
///
/// 컨트롤러와 `Autosave` 를 **세션마다 새로** 만들고 pop 에서 버린다.
/// 돌려 쓰지 않는 이유는 두 가지다:
///
///  - `ColoringController.dispose()` 가 `autosave.dispose()` 를 부른다.
///    하나를 공유하면 첫 세션이 끝나는 순간 `_disposed` 가 서고, 그 뒤
///    `schedule()` 은 조용히 아무 일도 하지 않는다 — 두 번째 작품부터
///    아이가 칠한 것이 오류 없이 사라진다.
///  - 컨트롤러가 한 번만 `open()` 되므로 계획 2 후속 §1.1·§3.3 과
///    계획 3 후속 §1.1 이 **발생할 수 없게** 된다.
class ColoringSession extends StatefulWidget {
  final DohanSource source;
  final ArtworkRepository repository;
  final AgeMode ageMode;
  final String dohanId;
  final String artworkId;

  const ColoringSession({
    super.key,
    required this.source,
    required this.repository,
    required this.ageMode,
    required this.dohanId,
    required this.artworkId,
  });

  @override
  State<ColoringSession> createState() => _ColoringSessionState();
}

class _ColoringSessionState extends State<ColoringSession> {
  late final ColoringController _controller;
  bool _opened = false;

  /// 도안을 끝내 열지 못했다. 스피너만 돌리면 이 화면에는 앱바도 완성
  /// 버튼도 PopScope 도 없어서 아이가 갇힌다.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = ColoringController(
      source: widget.source,
      autosave: Autosave(repository: widget.repository),
      ageMode: widget.ageMode,
    );
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _controller.open(
        dohanId: widget.dohanId,
        artworkId: widget.artworkId,
        existing: await widget.repository.load(widget.artworkId),
        stickers: await widget.repository.loadStickers(widget.artworkId),
        brushPng: await widget.repository.loadBrushPng(widget.artworkId),
      );
    } on Object catch (error) {
      // 읽기 자체가 실패했든(권한·잠김·디스크) 내용이 규칙을 어겼든, 아이가
      // 그 그림을 영영 못 여는 것이 가장 나쁜 결과다. 그렇다고 같은 id 로
      // 새로 시작하면 자동 저장이 잠깐 못 읽었을 뿐인 멀쩡한 파일 위에
      // 덮어쓴다. 복구용 id 로 비켜서 연다 — 아이는 계속 칠할 수 있고
      // 원본은 손대지 않는다.
      debugPrint('저장된 작품을 열지 못했습니다 — 새 작품으로 시작합니다: $error');
      try {
        await _controller.open(
          dohanId: widget.dohanId,
          artworkId: '${widget.artworkId}-복구-'
              '${DateTime.now().millisecondsSinceEpoch}',
        );
      } on Object catch (error) {
        // 도안 자체를 못 읽는 경우다 — 업데이트에서 빠졌거나 에셋이 깨졌다.
        debugPrint('도안을 열지 못했습니다: $error');
        if (mounted) setState(() => _failed = true);
        return;
      }
    }
    if (mounted) setState(() => _opened = true);
  }

  bool _finishing = false;

  /// 나가는 길. `완성` 버튼과 기기 뒤로가기가 함께 쓴다.
  ///
  /// `close()` 를 **먼저 기다린다.** 그냥 pop 하면 화면이 먼저 사라져서
  /// 썸네일을 구울 텍스처가 이미 해제된 뒤가 된다.
  ///
  /// 아이는 버튼을 두 번 누른다. 지금은 Navigator 가 중복 pop 을 흡수해
  /// 주지만(위젯 테스트로 확인), 그것은 내부 구현이다. 나가는 길이 한 번만
  /// 도는 것을 여기서 보장한다.
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;

    try {
      await _controller.close();
    } finally {
      // close() 가 던지거나 실패해도 나가는 길은 열려 있어야 한다.
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      // 글을 못 읽는 아이에게는 그림과 큰 버튼이 전부다.
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sentiment_dissatisfied_outlined,
                  size: 96, color: Color(0xFFB7BFB8)),
              const SizedBox(height: 16),
              const Text('그림을 열지 못했어요', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('open-failed-back'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(160, 64),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_opened) {
      // 도안을 읽고 마스크를 만드는 동안이다. 아이에게는 한 박자지만
      // 빈 화면을 주면 눌러 볼 것이 없다.
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_finish());
      },
      child: ColoringScreen(controller: _controller, onFinish: _finish),
    );
  }
}
