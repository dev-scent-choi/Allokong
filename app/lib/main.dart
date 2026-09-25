import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'coloring/coloring_controller.dart';
import 'gallery/artwork_repository.dart';
import 'gallery/autosave.dart';
import 'library/bundled_dohan_source.dart';
import 'ui/coloring_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final docs = await getApplicationDocumentsDirectory();
  final repository = ArtworkRepository(docs);
  final controller = ColoringController(
    source: BundledDohanSource(),
    autosave: Autosave(repository: repository),
  );

  const dohanId = 'flower-01';
  const artworkId = 'flower-01-1';
  await controller.open(
    dohanId: dohanId,
    artworkId: artworkId,
    existing: await repository.load(artworkId),
  );

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
