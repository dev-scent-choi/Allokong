/// 아이가 칠하고 있는 작품 하나.
///
/// 1단계에서는 채움 색만 담는다. 브러시 레이어와 스티커는 계획 3 이 같은
/// 폴더에 파일을 더 넣는 식으로 붙인다.
class Artwork {
  final String id;
  final String dohanId;

  /// 영역 ID → ARGB 정수.
  final Map<int, int> fills;

  final DateTime updatedAt;

  const Artwork({
    required this.id,
    required this.dohanId,
    required this.fills,
    required this.updatedAt,
  });

  Artwork copyWith({Map<int, int>? fills, DateTime? updatedAt}) => Artwork(
        id: id,
        dohanId: dohanId,
        fills: fills ?? this.fills,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'dohanId': dohanId,
        'fills': {for (final e in fills.entries) e.key.toString(): e.value},
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Artwork.fromJson(Map<String, dynamic> json) => Artwork(
        id: json['id'] as String,
        dohanId: json['dohanId'] as String,
        fills: {
          for (final e in (json['fills'] as Map).entries)
            int.parse(e.key as String): e.value as int
        },
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
