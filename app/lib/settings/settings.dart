import 'dart:convert';
import 'dart:io';

/// 연령대. 상위 스펙 9장.
enum AgeMode { toddler, child }

/// 보호자가 정하는 설정.
class Settings {
  final AgeMode ageMode;

  const Settings({this.ageMode = AgeMode.toddler});

  Map<String, dynamic> toJson() => {'ageMode': ageMode.name};

  factory Settings.fromJson(Map<String, dynamic> j) {
    final name = j['ageMode'];
    for (final m in AgeMode.values) {
      if (m.name == name) return Settings(ageMode: m);
    }
    // 모르는 값이면 기본값. 설정 하나가 이상하다고 앱이 안 뜨면 안 된다.
    return const Settings();
  }
}

/// `settings.json` 하나를 읽고 쓴다.
class SettingsStore {
  final Directory root;

  SettingsStore(this.root);

  File get _file => File('${root.path}/settings.json');

  /// 없거나 내용이 깨졌으면 기본값.
  ///
  /// 다만 **읽기 자체가 실패한 경우(권한·잠김·디스크)는 던진다.** 그것을
  /// 기본값으로 뭉개면 다음 `save` 가 멀쩡할 수도 있는 설정을 덮어쓴다 —
  /// 계획 2 의 `ArtworkRepository.load` 와 같은 원칙이다. 부르는 쪽이 잡는다.
  Future<Settings> load() async {
    final String text;
    try {
      text = await _file.readAsString();
    } on PathNotFoundException {
      return const Settings();
    }

    try {
      return Settings.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on FormatException {
      return const Settings();
    } on TypeError {
      return const Settings();
    }
  }

  Future<void> save(Settings settings) async {
    await root.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_file.path);
  }
}
