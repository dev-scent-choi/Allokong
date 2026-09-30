import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/settings/settings.dart';

void main() {
  late Directory root;
  late SettingsStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kkumul_set_');
    store = SettingsStore(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('아무것도 없으면 유아 모드다', () async {
    expect((await store.load()).ageMode, AgeMode.toddler,
        reason: '상위 스펙 9장의 기본값');
  });

  test('저장한 것을 다시 읽는다', () async {
    await store.save(const Settings(ageMode: AgeMode.child));
    expect((await store.load()).ageMode, AgeMode.child);
  });

  test('내용이 깨졌으면 기본값으로 돌아간다', () async {
    File('${root.path}/settings.json').writeAsStringSync('{{{');
    expect((await store.load()).ageMode, AgeMode.toddler);
  });

  test('모르는 연령 값이면 기본값으로 돌아간다', () async {
    File('${root.path}/settings.json').writeAsStringSync('{"ageMode":"우주인"}');
    expect((await store.load()).ageMode, AgeMode.toddler);
  });

  test('JSON 으로 왕복한다', () {
    const s = Settings(ageMode: AgeMode.child);
    expect(Settings.fromJson(s.toJson()).ageMode, AgeMode.child);
  });

  test('읽기 자체가 실패하면 던진다', () async {
    // 파일 자리에 디렉터리를 놓으면 읽기가 실패한다. 이때 조용히 기본값으로
    // 돌아가면 다음 save 가 멀쩡할 수도 있는 설정을 덮어쓴다 — 계획 2 의
    // ArtworkRepository.load 와 같은 원칙이다.
    Directory('${root.path}/settings.json').createSync();
    expect(store.load(), throwsA(isA<FileSystemException>()));
  });
}
