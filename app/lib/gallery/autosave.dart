import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/artwork.dart';
import 'artwork_repository.dart';

/// 조작이 멈추면 알아서 저장한다.
///
/// 아이는 저장 버튼을 누르지 않는다. 탭 한 번마다 파일을 쓰면 낭비이고,
/// 안 쓰면 앱이 죽었을 때 그림이 날아간다. 마지막 조작에서 [debounce] 만큼
/// 지나면 한 번 쓴다. 앱이 백그라운드로 갈 때는 [flush] 로 즉시 쓴다.
class Autosave {
  final ArtworkRepository repository;
  final Duration debounce;

  Timer? _timer;
  Artwork? _pending;
  bool _disposed = false;
  int _saveCount = 0;

  /// 쓰기를 한 줄로 세우는 큐.
  ///
  /// [ArtworkRepository.save] 는 고정된 이름(`artwork.json.tmp`)의 임시
  /// 파일에 쓰고 rename 한다. 같은 작품을 동시에 두 번 쓰면 임시 파일이
  /// 겹쳐 한쪽의 rename 이 PathNotFoundException 으로 죽고, 어느 내용이
  /// 남는지도 정해지지 않는다 — 오래된 그림이 새 그림을 이길 수 있다.
  /// 타이머가 쏜 저장이 끝나기 전에 생명주기 flush 가 겹치는 것은
  /// 충분히 일어나는 순서라, 그것을 여기서 막는다.
  Future<void> _queue = Future<void>.value();

  Autosave({
    required this.repository,
    this.debounce = const Duration(seconds: 1),
  });

  /// 지금까지 실제로 파일을 쓴 횟수. 디바운스가 동작하는지 확인하는 용도다.
  int get saveCount => _saveCount;

  void schedule(Artwork artwork) {
    if (_disposed) return;
    _pending = artwork;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush());
    });
  }

  /// 예약된 것이 있으면 기다리지 않고 지금 쓴다.
  ///
  /// 던지지 않는다. 부르는 쪽은 타이머 콜백과 생명주기 콜백 둘뿐이고,
  /// 둘 다 예외로 할 수 있는 일이 없다 — 어느 쪽에서 새어 나가도 처리되지
  /// 않는 비동기 오류가 될 뿐이다. 실패하면 되돌려 놓고 다음에 다시 쓴다.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _queue = _queue.then((_) => _writeOnce());
    return _queue;
  }

  /// 큐 안에서만 불린다. 여기서 [_pending] 을 읽으므로, 앞선 쓰기를
  /// 기다리는 동안 새로 예약된 것이 있으면 그 최신본이 쓰인다.
  Future<void> _writeOnce() async {
    final artwork = _pending;
    if (artwork == null) return;
    _pending = null;
    try {
      await repository.save(artwork);
      _saveCount++;
    } on Object catch (error) {
      // 새로 예약된 것이 있으면 그것이 더 새것이므로 덮지 않는다.
      if (!_disposed) _pending ??= artwork;
      debugPrint('작품 자동 저장 실패 — 다음 저장에서 다시 시도한다: $error');
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
