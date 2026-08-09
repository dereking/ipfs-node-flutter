import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

void main() {
  test('default platform throws an unimplemented error that names start', () {
    expect(
      () => IpfsNodePlatform.instance.start(PublicNodeConfig()),
      throwsA(
        isA<UnimplementedError>().having(
          (error) => error.message,
          'message',
          contains('start'),
        ),
      ),
    );
  });

  test('default platform reports every backend operation as unimplemented', () async {
    final platform = IpfsNodePlatform.instance;

    await expectLater(
      platform.stop(),
      throwsA(isA<UnimplementedError>().having(
        (error) => error.message,
        'message',
        contains('stop'),
      )),
    );
    await expectLater(
      platform.status(),
      throwsA(isA<UnimplementedError>().having(
        (error) => error.message,
        'message',
        contains('status'),
      )),
    );
    await expectLater(
      platform.capabilities(),
      throwsA(isA<UnimplementedError>().having(
        (error) => error.message,
        'message',
        contains('capabilities'),
      )),
    );
  });
}
