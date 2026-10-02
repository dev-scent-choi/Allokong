import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'coloring/coloring_controller.dart';
import 'gallery/artwork_repository.dart';
import 'gallery/autosave.dart';
import 'library/bundled_dohan_source.dart';
import 'settings/settings.dart';
import 'ui/coloring_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final docs = await getApplicationDocumentsDirectory();
  final repository = ArtworkRepository(docs);

  // SettingsStore.load() 도 ArtworkRepository.load() 와 같은 원칙으로 읽기
  // 자체가 실패하면(권한·잠김·디스크) 던진다. 따로 감싸서, 설정 파일 하나를
  // 못 읽는다고 앱이 영영 안 뜨는 일이 없게 한다 — 그때는 기본값으로 시작한다.
  var ageMode = AgeMode.toddler;
  try {
    ageMode = (await SettingsStore(docs).load()).ageMode;
  } on Object catch (error) {
    debugPrint('설정을 읽지 못했습니다 — 기본값으로 시작합니다: $error');
  }

  final controller = ColoringController(
    source: BundledDohanSource(),
    autosave: Autosave(repository: repository),
    ageMode: ageMode,
  );

  const dohanId = 'flower-01';
  const artworkId = 'flower-01-1';

  try {
    await controller.open(
      dohanId: dohanId,
      artworkId: artworkId,
      existing: await repository.load(artworkId),
      stickers: await repository.loadStickers(artworkId),
      brushPng: await repository.loadBrushPng(artworkId),
    );
  } on Object catch (error) {
    // 읽기 자체가 실패했든(권한·잠김·디스크) 내용이 규칙을 어겼든, 앱이 아예
    // 뜨지 않는 것이 가장 나쁜 결과다 — 아이는 이유를 모르고 부모는 고칠
    // 방법이 없다. 그렇다고 같은 id 로 새로 시작하면 자동 저장이 잠깐 못
    // 읽었을 뿐인 멀쩡한 파일 위에 덮어쓴다. 복구용 id 로 비켜서 연다:
    // 아이는 계속 칠할 수 있고 원본은 손대지 않는다.
    debugPrint('저장된 작품을 열지 못했습니다 — 새 작품으로 시작합니다: $error');
    await controller.open(
      dohanId: dohanId,
      artworkId: '$artworkId-복구-${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  runApp(KkumulApp(controller: controller));
}

class KkumulApp extends StatelessWidget {
  final ColoringController controller;

  const KkumulApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '꼬물꼬물',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246B4B)),
        useMaterial3: true,
      ),
      home: ColoringScreen(controller: controller),
    );
  }
}
