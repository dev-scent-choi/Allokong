import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/dohan_source.dart';
import 'gallery/artwork_repository.dart';
import 'library/bundled_dohan_source.dart';
import 'settings/settings.dart';
import 'shell/shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final docs = await getApplicationDocumentsDirectory();
  final settingsStore = SettingsStore(docs);

  // SettingsStore.load() 는 ArtworkRepository.load() 와 같은 원칙으로 읽기
  // 자체가 실패하면(권한·잠김·디스크) 던진다. 따로 감싸서, 설정 파일 하나를
  // 못 읽는다고 앱이 영영 안 뜨는 일이 없게 한다 — 그때는 기본값으로
  // 시작한다. 작품을 못 읽는 경우의 복구는 색칠 세션이 맡는다
  // (`coloring_route.dart` 의 -복구- 경로).
  var ageMode = AgeMode.toddler;
  try {
    ageMode = (await settingsStore.load()).ageMode;
  } on Object catch (error) {
    debugPrint('설정을 읽지 못했습니다 — 기본값으로 시작합니다: $error');
  }

  runApp(KkumulApp(
    source: BundledDohanSource(),
    repository: ArtworkRepository(docs),
    settingsStore: settingsStore,
    initialAgeMode: ageMode,
  ));
}

class KkumulApp extends StatelessWidget {
  final DohanSource source;
  final ArtworkRepository repository;
  final SettingsStore settingsStore;
  final AgeMode initialAgeMode;

  const KkumulApp({
    super.key,
    required this.source,
    required this.repository,
    required this.settingsStore,
    required this.initialAgeMode,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '꼬물꼬물',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246B4B)),
        useMaterial3: true,
      ),
      home: ShellScreen(
        source: source,
        repository: repository,
        settingsStore: settingsStore,
        initialAgeMode: initialAgeMode,
      ),
    );
  }
}
