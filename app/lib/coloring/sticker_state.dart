import 'dart:ui' show Offset, Rect;

/// 1단계 스티커 목록. 이 순서가 서랍에 보이는 순서다.
///
/// 열 개인 것은 화면 때문이다 — 320dp 에서 64dp 칸이 한 줄에 다섯이고
/// 상황별 영역이 두 줄이다. 더 넣으면 스크롤이 필요한데, 글을 못 읽는 아이에게
/// 스크롤되는 줄은 보이지 않는 것과 같다.
const List<String> kStickerIds = [
  'star-01',
  'heart-01',
  'flower-01',
  'dot-01',
  'diamond-01',
  'triangle-01',
  'moon-01',
  'ring-01',
  'cross-01',
  'cloud-01',
];

/// 캔버스에 붙인 스티커 하나.
///
/// 래스터로 굽지 않고 오브젝트로 둔다(상위 스펙 7.4). 개별 이동·삭제가 되고,
/// 되돌리기가 단순하며, 저장 용량이 사실상 0 이다.
class Sticker {
  /// 이 배치 한 건의 id. 같은 그림을 여러 번 붙일 수 있으므로 [stickerId] 와 다르다.
  final String instanceId;

  /// 어떤 스티커 그림인가. 예: `star-01`
  final String stickerId;

  /// 캔버스 좌표. 스티커의 **중심**이다.
  final double x;
  final double y;

  final double scale;

  /// 항상 `0` 이다. **생성자에서 강제한다** — 값을 받지 않는다.
  ///
  /// 포맷에는 남겨 둔다(`toJson` 이 계속 쓴다). 두 손가락으로 크기와 회전을
  /// 동시에 다루는 것은 6~9세에게 어렵고 대개 의도치 않게 비뚤어지기 때문에
  /// 지금은 제스처를 붙이지 않는다. 나중에 붙일 때는 이 강제를 풀기만 하면
  /// 되고 저장된 파일을 고칠 필요가 없다.
  ///
  /// 주석으로만 "항상 0"이라고 적어 두면 손으로 고친 `stickers.json` 이나
  /// 미래의 코드가 조용히 0 아닌 값을 들여보낸다. `scale` 은 모든 경로에서
  /// 클램프하면서 이것만 말로 때우는 것은 앞뒤가 맞지 않는다.
  final double rotation;

  static const double baseSize = 160;
  static const double minScale = 0.5;
  static const double maxScale = 2.0;

  Sticker({
    required this.instanceId,
    required this.stickerId,
    required this.x,
    required this.y,
    double scale = 1.0,
  })  : scale = scale.clamp(minScale, maxScale),
        rotation = 0;

  double get size => baseSize * scale;

  Rect get bounds =>
      Rect.fromCenter(center: Offset(x, y), width: size, height: size);

  bool contains(Offset p) => bounds.contains(p);

  Sticker copyWith({double? x, double? y, double? scale}) => Sticker(
        instanceId: instanceId,
        stickerId: stickerId,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
      );

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'stickerId': stickerId,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
      };

  factory Sticker.fromJson(Map<String, dynamic> j) => Sticker(
        instanceId: j['instanceId'] as String,
        stickerId: j['stickerId'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        scale: (j['scale'] as num).toDouble(),
      );
}

/// 붙인 스티커 목록. 뒤에 있는 것이 위에 그려진다.
class StickerState {
  final List<Sticker> stickers = [];

  /// [p] 아래에서 **맨 위** 스티커를 찾는다.
  Sticker? topAt(Offset p) {
    for (var i = stickers.length - 1; i >= 0; i--) {
      if (stickers[i].contains(p)) return stickers[i];
    }
    return null;
  }

  int indexOf(String instanceId) =>
      stickers.indexWhere((s) => s.instanceId == instanceId);

  /// 되돌리기가 z 순서까지 복원해야 하므로 자리를 지정해 넣는다.
  void insertAt(int index, Sticker s) => stickers.insert(index, s);

  void removeAt(int index) => stickers.removeAt(index);

  void replaceAt(int index, Sticker s) => stickers[index] = s;

  void clear() => stickers.clear();

  List<Map<String, dynamic>> toJson() =>
      [for (final s in stickers) s.toJson()];

  void loadJson(List<dynamic> json) {
    stickers.clear();
    for (final e in json) {
      stickers.add(Sticker.fromJson(e as Map<String, dynamic>));
    }
  }
}
