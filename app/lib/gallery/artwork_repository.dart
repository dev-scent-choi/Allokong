import 'dart:convert';
import 'dart:io';

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

  /// 작품을 쓴다. 임시 파일에 쓰고 rename 해서, 쓰는 도중 앱이 죽어도
  /// 반쯤 쓰인 파일이 남지 않게 한다.
  Future<void> save(Artwork artwork) async {
    final dir = _dirFor(artwork.id);
    await dir.create(recursive: true);

    final tmp = File('${dir.path}/artwork.json.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(artwork.toJson()),
      flush: true,
    );
    await tmp.rename(_fileFor(artwork.id).path);
  }

  Future<Artwork?> load(String id) async {
    final file = _fileFor(id);
    if (!file.existsSync()) return null;
    try {
      return Artwork.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      // 손상된 폴더 하나 때문에 나머지를 못 읽게 하지 않는다.
      return null;
    }
  }

  /// 최근에 고친 것부터.
  Future<List<Artwork>> listAll() async {
    if (!_artworksDir.existsSync()) return const [];
    final out = <Artwork>[];
    for (final entity in _artworksDir.listSync()) {
      if (entity is! Directory) continue;
      final artwork = await load(entity.path.split(Platform.pathSeparator).last);
      if (artwork != null) out.add(artwork);
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> delete(String id) async {
    final dir = _dirFor(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
