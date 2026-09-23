/// 도안 패키지를 파일 시스템에서 읽고 쓴다.
///
/// `dart:io` 에 의존하므로 본 배럴(`dohan_core.dart`)과 분리해 둔다. Flutter
/// 앱은 내장 도안을 에셋 번들에서 바이트로 받으므로 이 파일이 필요 없고,
/// `DohanPackage.fromBytes` 만 있으면 된다. 웹에서도 마찬가지다.
library dohan_core_io;

export 'src/dohan_package_io.dart';
