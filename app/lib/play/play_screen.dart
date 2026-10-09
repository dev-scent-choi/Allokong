import 'dart:async';

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';

import '../coloring/coloring_route.dart' show OpenColoring, newArtworkId;
import '../core/artwork.dart';
import '../core/dohan_source.dart';
import '../gallery/artwork_repository.dart';
import '../ui/art_tile.dart';

/// 카테고리 코드와 아이에게 보여줄 이름. 순서가 화면 순서다.
const _categories = <(String, String)>[
  ('animal', '동물'),
  ('car', '자동차'),
  ('dinosaur', '공룡'),
  ('shape', '모양'),
];

/// 도안을 고르는 화면. 상위 스펙 10.2 의 "가장 빠른 시작".
///
/// 위에서 아래로 이어 그리기 → 오늘의 도안 → 카테고리별 도안.
/// 전부 세로 스크롤 안이다 — 가로로 밀리는 줄은 글을 못 읽는 아이에게
/// 없는 것과 같다(계획 3 최종 리뷰).
class PlayScreen extends StatefulWidget {
  final DohanSource source;
  final ArtworkRepository repository;
  final OpenColoring onOpen;

  /// 셸이 색칠에서 돌아올 때마다 올려 주는 숫자. 바뀌면 다시 읽는다.
  final int refreshToken;

  /// 오늘의 도안을 고르는 기준 날짜. 테스트용이고, 주지 않으면 지금이다.
  final DateTime? today;

  const PlayScreen({
    super.key,
    required this.source,
    required this.repository,
    required this.onOpen,
    this.refreshToken = 0,
    this.today,
  });

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  List<DohanMeta>? _metas;
  Artwork? _recent;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PlayScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) unawaited(_loadRecent());
  }

  Future<void> _load() async {
    final ids = await widget.source.listIds();
    final metas = <DohanMeta>[];
    for (final id in ids) {
      metas.add(await widget.source.loadMeta(id));
    }
    if (!mounted) return;
    setState(() => _metas = metas);
    await _loadRecent();
  }

  Future<void> _loadRecent() async {
    // listAll 이 updatedAt 역순으로 준다.
    final all = await widget.repository.listAll();
    if (!mounted) return;
    setState(() => _recent = all.isEmpty ? null : all.first);
  }

  /// 오늘의 도안. 날짜를 씨앗으로 고르므로 하루 종일 같고 내일 바뀐다.
  ///
  /// 난수 상태를 저장할 필요가 없다는 것이 이 방식의 전부다.
  DohanMeta _todayDohan(List<DohanMeta> metas) {
    final now = (widget.today ?? DateTime.now()).toUtc();
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(1970))
        .inDays;
    return metas[days % metas.length];
  }

  void _openNew(DohanMeta meta) {
    widget.onOpen(dohanId: meta.id, artworkId: newArtworkId(meta.id));
  }

  @override
  Widget build(BuildContext context) {
    final metas = _metas;
    if (metas == null || metas.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final recent = _recent;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (recent != null) ...[
          const _Heading('이어 그리기'),
          ArtTile(
            key: const ValueKey('continue-tile'),
            label: '이어 그리기 ${recent.id}',
            onTap: () => widget.onOpen(
              dohanId: recent.dohanId,
              artworkId: recent.id,
            ),
            child: _lineart(recent.dohanId),
          ),
          const SizedBox(height: 16),
        ],
        const _Heading('오늘의 그림'),
        Builder(builder: (_) {
          final today = _todayDohan(metas);
          return ArtTile(
            key: const ValueKey('today-tile'),
            label: today.title,
            onTap: () => _openNew(today),
            child: _lineart(today.id),
          );
        }),
        for (final (code, name) in _categories) ...[
          const SizedBox(height: 16),
          _Heading(name),
          _Grid(
            metas: [for (final m in metas) if (m.category == code) m],
            onPick: _openNew,
            lineart: _lineart,
          ),
        ],
      ],
    );
  }

  Widget _lineart(String dohanId) => Image.asset(
        'assets/dohans/$dohanId/lineart.png',
        fit: BoxFit.cover,
        // 테스트의 가짜 라이브러리처럼 에셋이 없을 수 있다. 칸 자체는
        // 남아야 아이가 누를 곳을 잃지 않는다.
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFF2F2EE)),
      );
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// 한 카테고리의 도안들. 스스로 스크롤하지 않고 바깥 목록에 실린다.
class _Grid extends StatelessWidget {
  final List<DohanMeta> metas;
  final void Function(DohanMeta) onPick;
  final Widget Function(String) lineart;

  const _Grid({
    required this.metas,
    required this.onPick,
    required this.lineart,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final m in metas)
          ArtTile(
            label: m.title,
            onTap: () => onPick(m),
            child: lineart(m.id),
          ),
      ],
    );
  }
}
