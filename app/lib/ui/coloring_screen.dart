import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dohan_core/dohan_core.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../coloring/canvas_transform.dart';
import '../coloring/coloring_controller.dart';
import '../coloring/coloring_painter.dart';
import 'palette_bar.dart';

/// 도안 하나를 칠하는 화면.
class ColoringScreen extends StatefulWidget {
  final ColoringController controller;

  const ColoringScreen({super.key, required this.controller});

  @override
  State<ColoringScreen> createState() => _ColoringScreenState();
}

class _ColoringScreenState extends State<ColoringScreen>
    with WidgetsBindingObserver {
  ui.FragmentShader? _shader;
  ui.Image? _regionsImage;
  ui.Image? _lineartImage;
  ui.Image? _paletteImage;

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
    // dart:ui 는 ui.Image·FragmentShader 를 직접 해제하라고 요구한다. 위젯이
    // 사라지는 시점이라 다시 그릴 일이 없으므로 여기서는 안전하다.
    _shader?.dispose();
    _regionsImage?.dispose();
    _lineartImage?.dispose();
    _paletteImage?.dispose();
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

  void _onChanged() {
    if (!mounted) return;
    // 동기적으로 한 번 다시 그린다. 되돌리기 버튼의 활성 여부는 canUndo 에
    // 달려 있는데, 그것을 팔레트 이미지 디코딩이 끝난 뒤의 setState 에만
    // 맡기면 버튼이 한 박자 늦는다 — 위젯 테스트의 pump() 한 번으로는
    // 잡히지 않고, 실제 기기에서도 아이가 칠한 직후 버튼이 잠깐 죽어 있다.
    setState(() {});
    unawaited(_refreshPalette());
  }

  Future<void> _prepare() async {
    final dohan = widget.controller.dohan;
    if (dohan == null) return;

    final program = await ui.FragmentProgram.fromAsset('shaders/fill.frag');
    final regions = await _regionsToImage(dohan.regions);
    final lineart = await _lineartToImage(dohan.lineart);
    final palette = await widget.controller.fills.paletteImage();

    if (!mounted) return;
    setState(() {
      _shader = program.fragmentShader();
      _regionsImage = regions;
      _lineartImage = lineart;
      _paletteImage = palette;
    });
  }

  Future<void> _refreshPalette() async {
    final generation = ++_paletteGeneration;
    final palette = await widget.controller.fills.paletteImage();
    // 빠르게 연달아 탭하면 이미지 생성이 겹친다. 늦게 시작한 쪽이 최신이므로
    // 그 사이 세대가 올라갔으면 이 결과는 버린다.
    if (!mounted || generation != _paletteGeneration) return;
    setState(() => _paletteImage = palette);
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: PaletteBar(
                colors: PaletteBar.toddlerPalette,
                selected: c.selectedColor,
                onPick: c.pickColor,
              ),
            ),
          ],
        ),
      ),
    );
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
