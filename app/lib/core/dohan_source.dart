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
}
