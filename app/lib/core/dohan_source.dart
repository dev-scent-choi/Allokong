import 'package:dohan_core/dohan_core.dart';

/// 도안을 어디서 가져올지 감추는 경계.
///
/// 1단계 구현체는 앱에 내장된 에셋을 읽는 것 하나뿐이다. 사용자가 사진에서
/// 만든 도안(계획 4)과 원격 배포(미정)가 같은 인터페이스 뒤에 붙는다.
abstract class DohanSource {
  /// 이 소스가 가진 도안 ID 목록.
  Future<List<String>> listIds();

  /// 도안 한 벌을 읽는다. 없는 ID 면 [ArgumentError] 를 던진다.
  Future<DohanPackage> load(String id);

  /// 메타데이터만 읽는다. 없는 ID 면 [ArgumentError] 를 던진다.
  ///
  /// `놀기` 는 열두 장의 카테고리와 제목만 있으면 되는데, [load] 는 1024²
  /// PNG 두 장을 디코딩한다. 화면 하나 여는 데 그 비용을 열두 번 낼 이유가
  /// 없다.
  Future<DohanMeta> loadMeta(String id);
}
