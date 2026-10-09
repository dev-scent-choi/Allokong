import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import '../coloring/canvas_transform.dart';
import '../coloring/coloring_controller.dart';
import '../coloring/coloring_painter.dart';
import '../coloring/sticker_state.dart';
import '../gallery/thumbnail.dart';
import '../settings/settings.dart';
import 'palette_bar.dart';
import 'shade_button.dart';
import 'sticker_drawer.dart';
import 'tool_bar.dart';

/// 도안 하나를 칠하는 화면.
class ColoringScreen extends StatefulWidget {
  final ColoringController controller;

  /// 색칠을 마치고 나가는 길. 셸 위에 띄웠을 때만 준다.
  ///
  /// `null` 이면 `완성` 버튼을 보여주지 않는다 — 화면 하나만 띄우는
  /// 테스트가 그렇다.
  final Future<void> Function()? onFinish;

  const ColoringScreen({super.key, required this.controller, this.onFinish});

  @override
  State<ColoringScreen> createState() => _ColoringScreenState();
}

class _ColoringScreenState extends State<ColoringScreen>
    with WidgetsBindingObserver {
  ui.FragmentShader? _shader;
  ui.Image? _regionsImage;
  ui.Image? _lineartImage;
  ui.Image? _paletteImage;
  final Map<String, ui.Image> _stickerImages = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onChanged);
    unawaited(_prepare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onChanged);
    // 이미지를 해제하기 전에 뺀다. 그러지 않으면 생명주기 close() 가
    // 이미 해제된 텍스처로 그리려 든다.
    widget.controller.thumbnailBaker = null;
    // dart:ui 는 ui.Image·FragmentShader 를 직접 해제하라고 요구한다. 위젯이
    // 사라지는 시점이라 다시 그릴 일이 없으므로 여기서는 안전하다.
    _shader?.dispose();
    _regionsImage?.dispose();
    _lineartImage?.dispose();
    _paletteImage?.dispose();
    for (final img in _stickerImages.values) {
      img.dispose();
    }
    _stickerImages.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 물러날 때는 디바운스를 기다리지 않고 바로 쓴다.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(widget.controller.close());
    }
  }

  /// 팔레트 갱신이 겹쳤을 때 늦게 시작한 것이 이기도록 세대 번호를 둔다.
  int _paletteGeneration = 0;

  /// 마지막으로 팔레트를 구운 시점의 채움 개정 번호. 획을 긋는 동안은 이
  /// 값이 바뀌지 않으므로 다시 구울 필요가 없다는 것을 알 수 있다.
  int _paletteFillRevision = -1;

  void _onChanged() {
    if (!mounted) return;
    // 동기적으로 한 번 다시 그린다. 되돌리기 버튼의 활성 여부는 canUndo 에
    // 달려 있는데, 그것을 팔레트 이미지 디코딩이 끝난 뒤의 setState 에만
    // 맡기면 버튼이 한 박자 늦는다 — 위젯 테스트의 pump() 한 번으로는
    // 잡히지 않고, 실제 기기에서도 아이가 칠한 직후 버튼이 잠깐 죽어 있다.
    setState(() {});
    // 팔레트 텍스처는 채움에만 의존한다. 획을 긋는 동안 매 점마다 다시 구우면
    // 초당 쉰 장 넘게 버려진다 — 채움이 실제로 바뀌었을 때만 만든다.
    final revision = widget.controller.fills.revision;
    if (revision != _paletteFillRevision) {
      _paletteFillRevision = revision;
      unawaited(_refreshPalette());
    }
  }

  Future<void> _prepare() async {
    final dohan = widget.controller.dohan;
    if (dohan == null) return;

    final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
    final regions = await _regionsToImage(dohan.regions);
    final lineart = await _lineartToImage(dohan.lineart);
    final palette = await widget.controller.fills.paletteImage();

    final loadedStickers = <String, ui.Image>{};
    for (final id in kStickerIds) {
      final data = await rootBundle.load('assets/stickers/$id.png');
      loadedStickers[id] = await _decodeBytes(Uint8List.sublistView(data));
    }

    if (!mounted) return;
    // 여기서 구운 팔레트가 이미 반영하는 개정 번호를 기록해 둔다. 그렇지
    // 않으면 로드 뒤 첫 획이 "개정 번호가 바뀌었다"고 오판해 똑같은 팔레트를
    // 한 번 더 굽는다.
    _paletteFillRevision = widget.controller.fills.revision;
    setState(() {
      _shader = program.fragmentShader();
      _regionsImage = regions;
      _lineartImage = lineart;
      _paletteImage = palette;
      _stickerImages
        ..clear()
        ..addAll(loadedStickers);
    });
    // 텍스처가 다 올라온 지금부터 썸네일을 구울 수 있다.
    widget.controller.thumbnailBaker = _bakeThumbnail;
  }

  Future<void> _refreshPalette() async {
    final generation = ++_paletteGeneration;
    final palette = await widget.controller.fills.paletteImage();
    // 빠르게 연달아 탭하면 이미지 생성이 겹친다. 늦게 시작한 쪽이 최신이므로
    // 그 사이 세대가 올라갔으면 이 결과는 버린다.
    if (!mounted || generation != _paletteGeneration) return;
    setState(() => _paletteImage = palette);
  }

  /// 지금 화면에 보이는 그대로를 썸네일로 굽는다.
  Future<Uint8List?> _bakeThumbnail() async {
    final dohan = widget.controller.dohan;
    final shader = _shader;
    final regions = _regionsImage;
    final palette = _paletteImage;
    final lineart = _lineartImage;
    if (dohan == null ||
        shader == null ||
        regions == null ||
        palette == null ||
        lineart == null) {
      return null;
    }

    final c = widget.controller;
    return bakeThumbnail(
      ColoringPainter(
        shader: shader,
        regions: regions,
        palette: palette,
        lineart: lineart,
        canvasSize: dohan.regions.width,
        brush: c.state.brush,
        brushRevision: c.state.brush.revision,
        paintableMask: c.paintableMask,
        stickers: c.state.stickers.stickers,
        stickerImages: _stickerImages,
      ),
      dohan.regions.width,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return Scaffold(
      backgroundColor: const Color(0xFFFCFCF8),
      appBar: AppBar(
        // AppBar 의 기본 toolbarHeight(56)는 되돌리기 버튼의 세로 히트박스를
        // 64 로 키워도 그 안에서 눌러 찌그러뜨린다 — 툴바 자체를 64 로 키워야
        // 버튼이 실제로 64dp 높이를 얻는다.
        toolbarHeight: 64,
        title: Text(c.dohan?.meta.title ?? '색칠하기'),
        actions: [
          if (widget.onFinish != null)
            TextButton(
              key: const ValueKey('finish-button'),
              // 기본 TextButton 의 최소 높이는 36 이다. 스펙 10.3 의 64dp 를
              // 지키려면 직접 줘야 한다.
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 64),
                foregroundColor: const Color(0xFF246B4B),
                textStyle:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                unawaited(widget.onFinish!());
              },
              child: const Text('완성'),
            ),
          if (c.ageMode == AgeMode.child)
            ShadeButton(shade: c.shade, onCycle: c.cycleShade),
          IconButton(
            key: const ValueKey('undo-button'),
            icon: const Icon(Icons.undo),
            tooltip: '되돌리기',
            iconSize: 32,
            // IconButton 의 기본 히트 박스는 48×48 이다. iconSize 는 글리프만
            // 키우고 누를 수 있는 영역은 그대로라, 스펙의 64dp 최소값을 지키려면
            // 제약을 직접 줘야 한다. 아이 손가락은 어른보다 부정확하다.
            constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
            onPressed: c.canUndo
                ? () {
                    c.undo();
                  }
                : null,
          ),
        ],
      ),
      // AppBar 가 위쪽 인셋은 스스로 처리한다. 여기서 감싸는 것은 아래쪽 —
      // SafeArea 없이는 팔레트의 64dp 중 아래쪽이 시스템 제스처 바 밑으로
      // 들어가 실제 히트 영역이 줄어들고, 아이가 그 부분을 누르면 색 대신
      // 홈 제스처가 먹는다.
      body: SafeArea(
        child: Column(
          children: [
            // 도안만 읽히면 캔버스를 올린다. 셰이더와 텍스처는 아직 없을 수
            // 있고, 그때는 아무것도 그리지 않은 채 자리만 잡는다. 텍스처가
            // 올라오기를 기다렸다가 캔버스를 만들면 그 사이의 탭이 통째로
            // 사라진다 — 아이는 화면이 떴으면 누른다.
            Expanded(
              child: c.dohan == null
                  ? const Center(child: CircularProgressIndicator())
                  : _buildCanvas(c),
            ),
            if (c.ageMode == AgeMode.child)
              ToolBar(selected: c.tool, onSelect: c.selectTool),
            // 상황별 영역의 높이는 고정이다. 도구를 바꿀 때 높이가 변하면
            // 캔버스가 늘었다 줄었다 하면서 아이가 그리던 그림이 화면에서 튄다.
            SizedBox(height: 128, child: Center(child: _buildContext(c))),
          ],
        ),
      ),
    );
  }

  Widget _buildContext(ColoringController c) {
    switch (c.tool) {
      case ToolKind.sticker:
        return StickerDrawer(onPick: c.addSticker);
      case ToolKind.eraser:
        return const SizedBox.shrink();
      case ToolKind.bucket:
      case ToolKind.crayon:
      case ToolKind.brush:
        return PaletteBar(
          shade: c.shade,
          selectedIndex: c.colorIndex,
          onPickIndex: c.pickColorIndex,
        );
    }
  }

  Widget _buildCanvas(ColoringController c) {
    final canvasSize = c.dohan!.regions.width;
    final painted = _shader != null &&
        _regionsImage != null &&
        _lineartImage != null &&
        _paletteImage != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final transform = CanvasTransform.fit(
          Size(constraints.maxWidth, constraints.maxHeight),
          canvasSize,
        );

        return GestureDetector(
          key: const ValueKey('coloring-canvas'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => c.tapAt(transform.toCanvas(d.localPosition)),
          onTapUp: (d) {
            final c2 = c;
            if (c2.tool == ToolKind.bucket || c2.tool == ToolKind.sticker) {
              return;
            }
            // 아이는 끌기만 하지 않는다 — 톡 찍기도 한다. onTapUp 이라야
            // 끌기로 번진 경우에는 불리지 않는다(그때는 onPanStart 가 맡는다).
            final p = transform.toCanvas(d.localPosition);
            c2.beginStroke(p);
            c2.endStroke();
          },
          onPanStart: (d) {
            final p = transform.toCanvas(d.localPosition);
            if (c.tool == ToolKind.sticker) {
              c.beginStickerDrag(p);
            } else {
              c.beginStroke(p);
            }
          },
          onPanUpdate: (d) {
            final p = transform.toCanvas(d.localPosition);
            if (c.tool == ToolKind.sticker) {
              c.updateStickerDrag(x: p.dx, y: p.dy);
            } else {
              c.extendStroke(p);
            }
          },
          onPanEnd: (_) {
            if (c.tool == ToolKind.sticker) {
              c.endStickerDrag();
            } else {
              c.endStroke();
            }
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: painted
                ? FittedColoringPainter(
                    transform: transform,
                    inner: ColoringPainter(
                      shader: _shader!,
                      regions: _regionsImage!,
                      palette: _paletteImage!,
                      lineart: _lineartImage!,
                      canvasSize: canvasSize,
                      brush: c.state.brush,
                      brushRevision: c.state.brush.revision,
                      paintableMask: c.paintableMask,
                      stickers: c.state.stickers.stickers,
                      stickerImages: _stickerImages,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// 도안 페인터를 화면 크기에 맞춰 배치한다.
///
/// 페인터 자신은 도안의 논리 좌표계로만 그리고, 화면에 맞추는 변환은 여기서
/// 한 번에 건다. 셰이더 좌표도 이 변환을 그대로 따라간다.
///
/// 이름을 감추지 않는다 — 아이가 누른 곳과 칠해지는 곳이 맞는지는
/// `translate`/`scale` 두 줄의 순서에 달려 있고, 그 계약을 테스트가 직접
/// 그릴 수 있어야 한다(`fitted_coloring_painter_test.dart`).
class FittedColoringPainter extends CustomPainter {
  final CanvasTransform transform;
  final ColoringPainter inner;

  FittedColoringPainter({required this.transform, required this.inner});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.save();
    canvas.translate(transform.offset.dx, transform.offset.dy);
    canvas.scale(transform.scale);
    inner.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(FittedColoringPainter old) =>
      old.transform.scale != transform.scale ||
      old.transform.offset != transform.offset ||
      inner.shouldRepaint(old.inner);
}

/// 선화를 그대로 텍스처로 올린다.
///
/// PNG 로 인코딩했다가 곧바로 다시 디코딩하면 UI 아이소레이트에서 42ms 가
/// 그냥 날아간다(직접 올리면 5ms). 화면을 열 때마다 생기는 끊김이다.
Future<ui.Image> _lineartToImage(img.Image lineart) {
  final bytes = lineart.getBytes(order: img.ChannelOrder.rgba);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(bytes),
    lineart.width,
    lineart.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// PNG 바이트를 디코딩한다. 스티커 에셋을 읽는 데 쓴다.
Future<ui.Image> _decodeBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// 영역 맵을 셰이더가 읽을 RGBA 텍스처로 바꾼다.
///
/// R = ID 하위 8bit, G = ID 상위 8bit. dohan_core 의 인코딩과 같아야 한다.
Future<ui.Image> _regionsToImage(RegionMap regions) {
  final w = regions.width;
  final h = regions.height;
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final id = regions.ids[i];
    px[i * 4] = id & 0xFF;
    px[i * 4 + 1] = (id >> 8) & 0xFF;
    px[i * 4 + 2] = 0;
    px[i * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}
