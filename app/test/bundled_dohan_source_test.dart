import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/library/bundled_dohan_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('내장 도안 목록을 돌려준다', () async {
    final source = BundledDohanSource();

    expect(await source.listIds(), contains('flower-01'));
  });

  test('에셋 바이트에서 도안 한 벌을 만든다', () async {
    final pkg = await BundledDohanSource().load('flower-01');

    expect(pkg.meta.id, 'flower-01');
    expect(pkg.regions.width, 1024);
    expect(pkg.regions.height, 1024);
    expect(pkg.lineart.width, 1024);
    expect(pkg.regions.fillableRegionCount, greaterThanOrEqualTo(4));
  });

  test('없는 도안은 한국어로 알려준다', () async {
    expect(
      () => BundledDohanSource().load('없는도안'),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message, 'message', contains('없는도안'))),
    );
  });
}
