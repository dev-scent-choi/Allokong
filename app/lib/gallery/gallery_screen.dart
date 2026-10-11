import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../coloring/coloring_route.dart' show OpenColoring;
import '../core/artwork.dart';
import '../ui/art_tile.dart';
import 'artwork_repository.dart';

/// 내 작품을 모아 본다. 누르면 이어 그린다.
///
/// 작품별 삭제는 두지 않는다(설계 스펙 3절). 아이에게 영구 삭제는 되돌릴
/// 수 없고, 글을 못 읽으니 확인 대화상자도 작동하지 않는다. 정리는 글을
/// 읽는 사람이 쓰는 `내 정보` 에서 한다.
class GalleryScreen extends StatefulWidget {
  final ArtworkRepository repository;
  final OpenColoring onOpen;

  /// 셸이 색칠에서 돌아올 때마다 올려 주는 숫자. 바뀌면 다시 읽는다.
  ///
  /// 탭이 `IndexedStack` 안에 살아 있어서 스스로는 다시 지어지지 않는다 —
  /// 이것이 없으면 놀기에서 그린 그림이 모아보기에 영영 안 나타난다.
  final int refreshToken;

  const GalleryScreen({
    super.key,
    required this.repository,
    required this.onOpen,
    this.refreshToken = 0,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  /// `null` 이면 아직 읽는 중이다. 빈 목록과 구별해야 빈 상태 안내가
  /// 읽는 동안 잠깐 번쩍이지 않는다.
  List<Artwork>? _artworks;
  Map<String, Uint8List> _thumbs = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(GalleryScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) unawaited(_load());
  }

  Future<void> _load() async {
    final List<Artwork> list;
    try {
      list = await widget.repository.listAll();
    } on Object catch (error) {
      // 목록을 못 읽으면 보여 줄 것이 없다. 그래도 스피너를 영영 돌리는
      // 것보다 빈 상태를 보여주는 편이 낫다 — 아이는 놀기에서 새로
      // 시작할 수 있다.
      debugPrint('작품 목록을 읽지 못했습니다: $error');
      if (mounted) setState(() => _artworks = const []);
      return;
    }

    final thumbs = <String, Uint8List>{};
    for (final a in list) {
      try {
        final png = await widget.repository.loadThumbnail(a.id);
        if (png != null) thumbs[a.id] = png;
      } on Object catch (error) {
        // 썸네일 하나를 못 읽는다고 모아보기 전체가 멈추면 안 된다.
        // 없는 것으로 치면 그 도안의 선화로 대체된다.
        debugPrint('썸네일을 읽지 못했습니다(${a.id}): $error');
      }
    }

    if (!mounted) return;
    setState(() {
      _artworks = list;
      _thumbs = thumbs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final artworks = _artworks;
    if (artworks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (artworks.isEmpty) return const _EmptyGallery();

    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(12),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final a in artworks)
          ArtTile(
            label: '내 그림 ${a.id}',
            onTap: () =>
                widget.onOpen(dohanId: a.dohanId, artworkId: a.id),
            child: _thumbnailFor(a),
          ),
      ],
    );
  }

  /// 썸네일이 있으면 그것을, 없으면 그 도안의 선화를 보여준다.
  ///
  /// 썸네일이 없는 것은 앱이 강제 종료되어 `close()` 가 못 돈 경우다.
  /// 선화는 에셋으로 항상 있고, 아이는 그림 모양으로 자기 작품을
  /// 알아본다 — 색이 없을 뿐이다. 다음에 그 작품을 열고 나가면 생긴다.
  Widget _thumbnailFor(Artwork a) {
    final png = _thumbs[a.id];
    if (png != null) {
      return Image.memory(
        png,
        key: ValueKey('thumb-${a.id}'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Image.asset(
      'assets/dohans/${a.dohanId}/lineart.png',
      key: ValueKey('lineart-${a.id}'),
      fit: BoxFit.cover,
      // 144dp 칸에 1024 제곱을 통째로 디코딩하면 칸마다 4.2MB 다.
      cacheWidth: 288,
      cacheHeight: 288,
      // 도안이 사라진 작품(앱을 업데이트하며 도안을 뺀 경우)이라도
      // 칸은 남아야 한다. 누르면 색칠 쪽에서 제대로 알려 준다.
      errorBuilder: (_, __, ___) =>
          const ColoredBox(color: Color(0xFFF2F2EE)),
    );
  }
}

/// 작품이 하나도 없을 때. 상위 스펙 10.2 의 필수 요소다.
class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('gallery-empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 글을 못 읽는 아이에게는 이 그림이 문구보다 많이 말한다.
          const Icon(Icons.palette_outlined,
              size: 96, color: Color(0xFFB7BFB8)),
          const SizedBox(height: 16),
          Text(
            '아직 그린 그림이 없어요',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('놀기에서 그림을 골라 보세요',
              style: TextStyle(color: Color(0xFF6B736C))),
        ],
      ),
    );
  }
}
