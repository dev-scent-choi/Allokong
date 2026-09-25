import 'dart:async';

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
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final artwork = _pending;
    if (artwork == null) return;
    _pending = null;
    await repository.save(artwork);
    _saveCount++;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
