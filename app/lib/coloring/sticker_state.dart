import 'dart:ui' show Offset, Rect;

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

  /// 항상 0. 포맷 호환을 위해 자리만 둔다 — 두 손가락으로 크기와 회전을 동시에
  /// 다루는 것은 6~9세에게 어렵고 대개 의도치 않게 비뚤어진다. 나중에 포맷을
  /// 바꾸지 않고 제스처만 추가할 수 있다.
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
    this.rotation = 0,
  }) : scale = scale.clamp(minScale, maxScale);

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
        rotation: rotation,
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
        rotation: (j['rotation'] as num).toDouble(),
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
