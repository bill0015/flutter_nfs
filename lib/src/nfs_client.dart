import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'nfs_bindings.dart';
import 'nfs_file.dart';

/// Entry in an NFS directory listing
class NfsEntry {
  final String name;
  final int size;
  final bool isDirectory;
  final int mode;
  final DateTime modifiedTime;

  NfsEntry({
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.mode,
    required this.modifiedTime,
  });

  @override
  String toString() =>
      'NfsEntry(name: $name, size: $size, isDirectory: $isDirectory)';
}

/// High-level NFS client with zero-copy optimizations.
///
/// Example usage:
/// ```dart
/// final client = NfsClient();
/// client.mountSync('nfs://192.168.1.100/roms?nfsport=2049');
///
/// // List files
/// final entries = client.listDir('/');
///
/// // Open and read a file with zero-copy
/// final file = client.open('/game.rom');
/// final buffer = calloc<Uint8>(file.size);
/// file.pread(buffer, file.size, 0);
/// // ... use buffer ...
/// calloc.free(buffer);
/// file.close();
///
/// client.dispose();
/// ```
/// Low-level synchronous NFS client wrapping libnfs FFI.
///
/// **WARNING**: This class contains blocking synchronous calls.
/// Do NOT use this on the main UI thread. It is intended for use
/// within Isolates or Workers (like the Game Engine).
///
/// For standard App development, use [NfsClient].
class NfsNativeClient {
  late final NfsBindings _bindings;

  /// Expose bindings for advanced usage (e.g. Worker Isolate)
  NfsBindings get bindings => _bindings;

  late final Pointer<NfsContext> _context;
  bool _isMounted = false;

  bool _isDisposed = false;

  NfsNativeClient() {
    _bindings = NfsBindings();
    _context = _bindings.nfs_init_context();
    if (_context == nullptr) {
      throw NfsException('Failed to create NFS context');
    }
  }

  /// Whether the client is connected to an NFS share
  bool get isMounted => _isMounted;

  /// Logger callback
  static void Function(String message)? onLog;

  static void _log(String message) {
    if (onLog != null) {
      onLog!('[NfsNativeClient] $message');
    } else {
      // ignore: avoid_print
      print('[NfsNativeClient] $message');
    }
  }

  /// Initialize the C++ Block Cache.
  /// [capacityMb] defaults to 64MB if <= 0.
  void initCache(int capacityMb) {
    if (_bindings.cache_init != null) {
      _bindings.cache_init!(capacityMb);
    }
  }

  /// Read directly from the Block Cache (Zero-Copy from Cache).
  /// Returns number of bytes read, or -1 if any block is missing.
  int readCached(int offset, int len, Pointer<Uint8> buffer) {
    if (_bindings.cache_read != null) {
      return _bindings.cache_read!(offset, len, buffer);
    }
    return -1;
  }

  /// Safe string decoding
  String _safeToString(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return '';
    int len = 0;
    while (ptr.cast<Uint8>().elementAt(len).value != 0) {
      len++;
    }
    final bytes = ptr.cast<Uint8>().asTypedList(len);
    try {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } catch (e) {
      return 'Decode error: $e';
    }
  }

  /// Get the last error message from libnfs
  String get lastError {
    final errPtr = _bindings.nfs_get_error(_context);
    if (errPtr == nullptr) return 'Unknown error (null pointer)';
    return _safeToString(errPtr);
  }

  /// Mount an NFS share synchronously.
  ///
  /// The URL format is: `nfs://server/export[?options]`
  ///
  /// Options include:
  /// - `nfsport=<port>` - NFS port (bypasses portmapper)
  /// - `mountport=<port>` - Mount port (bypasses portmapper)
  /// - `version=3|4` - NFS version
  /// - `uid=<uid>` - UID for NFS operations
  /// - `gid=<gid>` - GID for NFS operations
  ///
  /// Use [NfsUrl.build] to construct URLs easily.
  void mountSync(String url) {
    _ensureNotDisposed();
    if (_isMounted) {
      throw StateError('Already mounted. Call unmount() first.');
    }

    final encodedUrl = Uri.encodeFull(url);
    final uri = Uri.parse(encodedUrl);
    final server = uri.host;
    final path = uri.path;

    _log('Parsed server: $server, path: $path');

    final serverPtr = server.toNativeUtf8();
    final exportPtr = path.toNativeUtf8();

    try {
      _log('Calling nfs_mount...');
      final result = _bindings.nfs_mount(_context, serverPtr, exportPtr);
      _log('nfs_mount result: $result');

      if (result != 0) {
        final error = lastError;
        _log('Mount failed: $error');
        throw NfsException('Mount failed: $error');
      }
      _isMounted = true;
      _log('Mount successful');
    } finally {
      calloc.free(serverPtr);
      calloc.free(exportPtr);
    }
  }

  /// Unmount the current share
  void unmount() {
    if (!_isMounted) return;
    _bindings.nfs_umount(_context);
    _isMounted = false;
  }

  /// Check if a path exists
  bool exists(String path) {
    try {
      final file = open(path);
      file.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Create a file and open it for writing.
  NfsFile createFile(String path, {int mode = 420 /* 0644 */}) {
    _ensureNotDisposed();
    _ensureMounted();

    final pathPtr = path.toNativeUtf8();
    final handlePtr = calloc<Pointer<NfsFh>>();

    try {
      // Use standard nfs_creat
      final result = _bindings.nfs_creat(_context, pathPtr, mode, handlePtr);
      if (result != 0) {
        throw NfsException('Failed to create $path: $lastError');
      }

      final handle = handlePtr.value;
      // Newly created file size is 0
      return NfsFile(
        bindings: _bindings,
        context: _context,
        handle: handle,
        size: 0,
      );
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
    }
  }

  /// Open a file with specific flags (O_RDONLY, O_WRONLY, O_RDWR)
  NfsFile open(String path, {int flags = O_RDONLY}) {
    _ensureNotDisposed();
    _ensureMounted();

    final pathPtr = path.toNativeUtf8();
    final handlePtr = calloc<Pointer<NfsFh>>();

    try {
      final result = _bindings.nfs_open(_context, pathPtr, flags, handlePtr);
      if (result != 0) {
        throw NfsException('Failed to open $path: $lastError');
      }

      final handle = handlePtr.value;

      // Get file size
      final stat = calloc<NfsStat64>();
      try {
        final statResult = _bindings.nfs_fstat64(_context, handle, stat);
        if (statResult != 0) {
          _bindings.nfs_close(_context, handle);
          throw NfsException('Failed to stat $path: $lastError');
        }
        final size = stat.ref.nfs_size;
        return NfsFile(
          bindings: _bindings,
          context: _context,
          handle: handle,
          size: size,
        );
      } finally {
        calloc.free(stat);
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
    }
  }

  /// List directory contents.
  List<NfsEntry> listDir(String path) {
    _ensureNotDisposed();
    _ensureMounted();

    final pathPtr = path.toNativeUtf8();
    final dirPtr = calloc<Pointer<NfsDir>>();

    try {
      final result = _bindings.nfs_opendir(_context, pathPtr, dirPtr);
      if (result != 0) {
        throw NfsException('Failed to open directory $path: $lastError');
      }

      final dir = dirPtr.value;
      final entries = <NfsEntry>[];

      while (true) {
        final dirent = _bindings.nfs_readdir(_context, dir);
        if (dirent == nullptr) break;

        final name = _safeToString(dirent.ref.name);
        // Skip . and ..
        if (name == '.' || name == '..') continue;

        entries.add(
          NfsEntry(
            name: name,
            size: dirent.ref.size,
            isDirectory: (dirent.ref.type & 0x4000) != 0, // S_IFDIR
            mode: dirent.ref.mode,
            modifiedTime: DateTime.fromMillisecondsSinceEpoch(
              dirent.ref.mtime * 1000,
            ),
          ),
        );
      }

      _bindings.nfs_closedir(_context, dir);
      return entries;
    } finally {
      calloc.free(pathPtr);
      calloc.free(dirPtr);
    }
  }

  // --- Management Operations ---

  void delete(String path) {
    _ensureNotDisposed();
    _ensureMounted();
    final pathPtr = path.toNativeUtf8();
    try {
      final res = _bindings.nfs_unlink(_context, pathPtr);
      if (res != 0) throw NfsException('Delete failed: $lastError');
    } finally {
      calloc.free(pathPtr);
    }
  }

  void mkdir(String path) {
    _ensureNotDisposed();
    _ensureMounted();
    final pathPtr = path.toNativeUtf8();
    try {
      final res = _bindings.nfs_mkdir(_context, pathPtr);
      if (res != 0) throw NfsException('Mkdir failed: $lastError');
    } finally {
      calloc.free(pathPtr);
    }
  }

  void rmdir(String path) {
    _ensureNotDisposed();
    _ensureMounted();
    final pathPtr = path.toNativeUtf8();
    try {
      final res = _bindings.nfs_rmdir(_context, pathPtr);
      if (res != 0) throw NfsException('Rmdir failed: $lastError');
    } finally {
      calloc.free(pathPtr);
    }
  }

  void rename(String oldPath, String newPath) {
    _ensureNotDisposed();
    _ensureMounted();
    final oldPtr = oldPath.toNativeUtf8();
    final newPtr = newPath.toNativeUtf8();
    try {
      final res = _bindings.nfs_rename(_context, oldPtr, newPtr);
      if (res != 0) throw NfsException('Rename failed: $lastError');
    } finally {
      calloc.free(oldPtr);
      calloc.free(newPtr);
    }
  }

  void truncate(String path, int length) {
    _ensureNotDisposed();
    _ensureMounted();
    final pathPtr = path.toNativeUtf8();
    try {
      final res = _bindings.nfs_truncate(_context, pathPtr, length);
      if (res != 0) throw NfsException('Truncate failed: $lastError');
    } finally {
      calloc.free(pathPtr);
    }
  }

  void chmod(String path, int mode) {
    _ensureNotDisposed();
    _ensureMounted();
    final pathPtr = path.toNativeUtf8();
    try {
      final res = _bindings.nfs_chmod(_context, pathPtr, mode);
      if (res != 0) throw NfsException('Chmod failed: $lastError');
    } finally {
      calloc.free(pathPtr);
    }
  }

  void chown(String path, int uid, int gid) {
    _ensureNotDisposed();
    _ensureMounted();
    final pathPtr = path.toNativeUtf8();
    try {
      final res = _bindings.nfs_chown(_context, pathPtr, uid, gid);
      if (res != 0) throw NfsException('Chown failed: $lastError');
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Parse an NFS URL into components
  NfsParsedUrl parseUrl(String url) {
    _ensureNotDisposed();
    final encodedUrl = Uri.encodeFull(url);
    final urlPtr = encodedUrl.toNativeUtf8();
    try {
      final res = _bindings.nfs_parse_url_dir(_context, urlPtr);
      if (res == nullptr) {
        throw NfsException('Failed to parse URL: $url');
      }
      try {
        return NfsParsedUrl(
          _safeToString(res.ref.server),
          _safeToString(res.ref.path),
          _safeToString(res.ref.file),
        );
      } finally {
        _bindings.nfs_destroy_url(res);
      }
    } finally {
      calloc.free(urlPtr);
    }
  }

  /// Provide a path hint to the C++ VFS to avoid blocking URL parsing inside retro_vfs_open.
  void addPathHint(
      String fullUrl, String server, String exportPath, String relativePath) {
    _ensureNotDisposed();
    final urlPtr = fullUrl.toNativeUtf8();
    final serverPtr = server.toNativeUtf8();
    final exportPtr = exportPath.toNativeUtf8();
    final relativePtr = relativePath.toNativeUtf8();

    try {
      if (_bindings.nfs_vfs_add_path_hint != null) {
        _bindings.nfs_vfs_add_path_hint!(
            urlPtr, serverPtr, exportPtr, relativePtr);
      }
    } finally {
      calloc.free(urlPtr);
      calloc.free(serverPtr);
      calloc.free(exportPtr);
      calloc.free(relativePtr);
    }
  }

  /// Clean up resources
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    if (_isMounted) {
      unmount();
    }
    _bindings.nfs_destroy_context(_context);
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('NfsClient has been disposed');
    }
  }

  void _ensureMounted() {
    if (!_isMounted) {
      throw StateError('Not mounted. Call mountSync() first.');
    }
  }
}

class NfsParsedUrl {
  final String server;

  /// Export path (e.g. /volume1/data)
  final String path;

  /// File path relative to export (e.g. /roms/game.iso)
  final String file;

  NfsParsedUrl(this.server, this.path, this.file);
}
