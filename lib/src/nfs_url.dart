/// NFS URL builder with optimization parameters
class NfsUrl {
  /// Build an NFS URL with optional port parameters to bypass portmapper.
  ///
  /// Bypassing portmapper saves ~200-500ms on connection establishment.
  ///
  /// Example:
  /// ```dart
  /// final url = NfsUrl.build(
  ///   host: '192.168.1.100',
  ///   path: '/roms',
  ///   nfsPort: 2049,
  ///   mountPort: 20048,
  /// );
  /// // Result: "nfs://192.168.1.100/roms?nfsport=2049&mountport=20048"
  /// ```
  static String build({
    required String host,
    required String path,
    int? nfsPort,
    int? mountPort,
    int version = 3,
    int? uid,
    int? gid,
    bool? autoTraverseMounts,
  }) {
    // Ensure path starts with /
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    // Build query parameters
    final params = <String>[];

    if (version != 3) {
      params.add('version=$version');
    }
    if (nfsPort != null) {
      params.add('nfsport=$nfsPort');
    }
    if (mountPort != null) {
      params.add('mountport=$mountPort');
    }
    if (uid != null) {
      params.add('uid=$uid');
    }
    if (gid != null) {
      params.add('gid=$gid');
    }
    if (autoTraverseMounts != null) {
      params.add('auto-traverse-mounts=${autoTraverseMounts ? 1 : 0}');
    }

    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    return 'nfs://$host$normalizedPath$query';
  }

  /// Build URL for NFSv4 (no mount protocol needed)
  static String buildV4({
    required String host,
    required String path,
    int? nfsPort,
    int? uid,
    int? gid,
  }) {
    return build(
      host: host,
      path: path,
      nfsPort: nfsPort,
      uid: uid,
      gid: gid,
      version: 4,
    );
  }
}
