import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkumul/library/bundled_dohan_source.dart';

/// 에셋을 "더 큰 버퍼의 조각"으로 돌려주는 번들.
///
/// 실제 기기의 rootBundle 은 이런 ByteData 를 줄 수 있다. 테스트 목은 항상
/// 정확한 크기의 새 버퍼를 주므로, 이 함정은 일부러 만들어야 드러난다.
class _SlicedAssetBundle extends CachingAssetBundle {
  final AssetBundle inner;

  _SlicedAssetBundle(this.inner);

  @override
  Future<ByteData> load(String key) async {
    final data = await inner.load(key);
    final src = Uint8List.sublistView(data);
    const padFront = 7;
    const padBack = 5;
    final big = Uint8List(padFront + src.length + padBack)
      ..fillRange(0, padFront, 0xAB)
      ..fillRange(padFront + src.length, padFront + src.length + padBack, 0xCD);
    big.setRange(padFront, padFront + src.length, src);
    return ByteData.sublistView(big, padFront, padFront + src.length);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('내장 도안 목록을 돌려준다', () async {
    final source = BundledDohanSource();

    expect(await source.listIds(), contains('flower-01'));
  });

  test('에셋 바이트에서 도안 한 벌을 만든다', () async {
    final pkg = await BundledDohanSource().load('flower-01');

    expect(pkg.meta.id, 'flower-01');
    expect(pkg.meta.title, '동그라미 꽃');
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

  test('에셋이 큰 버퍼의 조각으로 와도 올바르게 읽는다', () async {
    final source = BundledDohanSource(bundle: _SlicedAssetBundle(rootBundle));

    final pkg = await source.load('flower-01');

    expect(pkg.meta.id, 'flower-01');
    expect(pkg.meta.title, '동그라미 꽃',
        reason: '한국어가 깨지면 utf8 디코딩이나 오프셋이 잘못된 것이다');
    expect(pkg.regions.width, 1024);
    expect(pkg.regions.fillableRegionCount, greaterThanOrEqualTo(4));
  });
}
