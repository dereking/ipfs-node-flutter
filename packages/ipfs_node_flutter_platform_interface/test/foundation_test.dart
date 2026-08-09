import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

void main() {
  test('default platform throws an unimplemented error that names start', () {
    expect(
      () => IpfsNodePlatform.instance.start(const PublicNodeConfig()),
      throwsA(
        isA<UnimplementedError>().having(
          (error) => error.message,
          'message',
          contains('start'),
        ),
      ),
    );
  });
}
