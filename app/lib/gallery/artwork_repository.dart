import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../coloring/sticker_state.dart';
import '../core/artwork.dart';

/// 작품을 폴더 단위로 저장한다.
///
/// 작품 하나 = 폴더 하나이고, 목록은 디렉터리를 훑어 만든다. 중앙 인덱스
/// 파일을 두지 않는 것은 의도된 선택이다 — 인덱스가 하나 있으면 그것이
/// 깨졌을 때 아이의 작품 전체가 한 번에 사라진다. 폴더 하나가 손상돼도
/// 나머지는 멀쩡하다.
class ArtworkRepository {
  final Directory root;

  ArtworkRepository(this.root);

  Directory get _artworksDir => Directory('${root.path}/artworks');

  Directory _dirFor(String id) => Directory('${_artworksDir.path}/$id');

  File _fileFor(String id) => File('${_dirFor(id).path}/artwork.json');

  File _stickersFileFor(String id) => File('${_dirFor(id).path}/stickers.json');

  File _brushFileFor(String id) => File('${_dirFor(id).path}/brush.png');

  /// 작품을 쓴다. 임시 파일에 쓰고 rename 해서, 쓰는 도중 앱이 죽어도
  /// 반쯤 쓰인 파일이 남지 않게 한다.
  ///
  /// [brushPng] 가 `null` 이면 `brush.png` 를 **건드리지 않는다.** "지워라"가
  /// 아니라 "바뀐 게 없다"는 뜻이다 — 굽는 데 53ms 가 들어서, 바뀌지 않았으면
  /// 아예 만들지 않고 여기까지 오지 않는다.
  ///
  /// rename 은 파일 하나 안에서만 원자적이다. 셋을 연달아 쓰다 앱이 죽으면
  /// 레이어마다 마지막 1초가 다르게 남을 수 있는데, 그것은 파일이 깨진 것이
  /// 아니라 "방금 그은 획 하나가 없는" 상태다. 폴더 단위 원자화는 그 복잡도를
  /// 낼 값이 아니라고 판단했다.
  Future<void> save(
    Artwork artwork, {
    List<Sticker> stickers = const [],
    Uint8List? brushPng,
  }) async {
    final dir = _dirFor(artwork.id);
    await dir.create(recursive: true);

    final tmp = File('${dir.path}/artwork.json.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(artwork.toJson()),
      flush: true,
    );
    await tmp.rename(_fileFor(artwork.id).path);

    final stickersFile = _stickersFileFor(artwork.id);
    if (stickers.isEmpty) {
      if (stickersFile.existsSync()) await stickersFile.delete();
    } else {
      final stmp = File('${dir.path}/stickers.json.tmp');
      await stmp.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert([for (final s in stickers) s.toJson()]),
        flush: true,
      );
      await stmp.rename(stickersFile.path);
    }

    if (brushPng != null) {
      final btmp = File('${dir.path}/brush.png.tmp');
      await btmp.writeAsBytes(brushPng, flush: true);
      await btmp.rename(_brushFileFor(artwork.id).path);
    }
  }

  /// 작품 하나를 읽는다.
  ///
  /// 파일이 없으면 null. 내용이 깨졌으면 null — 폴더 하나의 손상이 나머지를
  /// 못 읽게 하지 않는다는 것이 이 저장소의 설계다.
  ///
  /// 다만 **읽기 자체가 실패한 경우(권한, 잠김, 디스크)는 던진다.** 그것을
  /// null 로 뭉개면 호출자가 "작품이 없다"로 읽고 새로 시작한 뒤 멀쩡한
  /// 파일 위에 덮어쓴다 — 이 설계가 막으려던 바로 그 데이터 손실이다.
  Future<Artwork?> load(String id) async {
    final String text;
    try {
      text = await _fileFor(id).readAsString();
    } on PathNotFoundException {
      return null;
    }

    try {
      return Artwork.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 스티커 목록. 없거나 내용이 깨졌으면 빈 목록.
  ///
  /// 파일 셋을 독립적으로 취급한다 — 스티커가 깨져도 채움과 브러시는 살아난다.
  Future<List<Sticker>> loadStickers(String id) async {
    final String text;
    try {
      text = await _stickersFileFor(id).readAsString();
    } on PathNotFoundException {
      return const [];
    }

    try {
      final list = jsonDecode(text) as List<dynamic>;
      return [
        for (final e in list) Sticker.fromJson(e as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  /// 구운 브러시 레이어. 없으면 null.
  Future<Uint8List?> loadBrushPng(String id) async {
    try {
      return await _brushFileFor(id).readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  /// 최근에 고친 것부터.
  Future<List<Artwork>> listAll() async {
    if (!_artworksDir.existsSync()) return const [];
    final out = <Artwork>[];
    for (final entity in _artworksDir.listSync()) {
      if (entity is! Directory) continue;
      final id = entity.path.split(Platform.pathSeparator).last;
      try {
        final artwork = await load(id);
        if (artwork != null) out.add(artwork);
      } on FileSystemException {
        // 폴더 하나를 못 읽어도 목록 전체를 못 만들게 하지 않는다.
        // 읽기 실패를 감추는 것은 load 가 아니라 여기 — 목록은 최선을 다해
        // 보여주고, 단일 작품을 열 때는 실패를 그대로 알린다.
        continue;
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> delete(String id) async {
    final dir = _dirFor(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
