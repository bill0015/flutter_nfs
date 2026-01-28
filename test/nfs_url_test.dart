import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_nfs/flutter_nfs.dart';

void main() {
  group('NfsUrl', () {
    test('build constructs basic URL', () {
      final url = NfsUrl.build(
        host: '192.168.1.10',
        path: '/volume1/data',
      );
      expect(url, 'nfs://192.168.1.10/volume1/data');
    });

    test('build handles path without leading slash', () {
      final url = NfsUrl.build(
        host: '192.168.1.10',
        path: 'volume1/data',
      );
      expect(url, 'nfs://192.168.1.10/volume1/data');
    });

    test('build includes NFS port', () {
      final url = NfsUrl.build(
        host: 'server',
        path: '/share',
        nfsPort: 2049,
      );
      expect(url, 'nfs://server/share?nfsport=2049');
    });

    test('build includes mount port', () {
      final url = NfsUrl.build(
        host: 'server',
        path: '/share',
        mountPort: 20048,
      );
      expect(url, 'nfs://server/share?mountport=20048');
    });

    test('build includes multiple parameters', () {
      final url = NfsUrl.build(
        host: 'server',
        path: '/share',
        nfsPort: 2049,
        version: 3, // Default, should not appear
        uid: 1000,
        gid: 1000,
      );
      // Order depends on implementation, but typically consistent
      expect(url, 'nfs://server/share?nfsport=2049&uid=1000&gid=1000');
    });

    test('build handles explicit version', () {
      final url = NfsUrl.build(
        host: 'server',
        path: '/share',
        version: 4,
      );
      expect(url, 'nfs://server/share?version=4');
    });

    test('buildV4 creates version 4 URL', () {
      final url = NfsUrl.buildV4(
        host: 'server',
        path: '/share',
        nfsPort: 2049,
      );
      expect(url, 'nfs://server/share?version=4&nfsport=2049');
    });
  });
}
