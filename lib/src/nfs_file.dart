import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'nfs_bindings.dart';

/// A file opened from an NFS share with zero-copy read support.
///
/// For optimal performance, use [pread] with a pre-allocated pointer
/// to avoid memory copies.
class NfsFile {
  final NfsBindings _bindings;
  final Pointer<NfsContext> _context;
  final Pointer<NfsFh> _handle;
  final int _size;
  bool _isClosed = false;

  NfsFile({
    required NfsBindings bindings,
    required Pointer<NfsContext> context,
    required Pointer<NfsFh> handle,
    required int size,
  })  : _bindings = bindings,
        _context = context,
        _handle = handle,
        _size = size;

  /// File size in bytes
  int get size => _size;

  /// Whether this file handle has been closed
  bool get isClosed => _isClosed;

  /// Zero-copy read: writes data directly into the provided buffer.
  ///
  /// This is the most performant read method. The caller is responsible
  /// for allocating and freeing the buffer.
  ///
  /// Example:
  /// ```dart
  /// final buffer = calloc<Uint8>(4096);
  /// try {
  ///   final bytesRead = file.pread(buffer, 4096, 0);
  ///   // Use buffer.asTypedList(bytesRead) or pass to native code
  /// } finally {
  ///   calloc.free(buffer);
  /// }
  /// ```
  ///
  /// Returns the number of bytes actually read, or -1 on error.
  int pread(Pointer<Uint8> buffer, int count, int offset) {
    _ensureOpen();
    return _bindings.nfs_pread(_context, _handle, buffer, count, offset);
  }

  /// Convenience read that returns a Uint8List.
  ///
  /// Note: This involves a memory copy. For maximum performance,
  /// use [pread] with a pre-allocated buffer.
  Uint8List read(int count, int offset) {
    _ensureOpen();
    final buffer = calloc<Uint8>(count);
    try {
      final bytesRead = pread(buffer, count, offset);
      if (bytesRead < 0) {
        throw NfsException('Read failed');
      }
      // Copy to Dart-managed memory
      return Uint8List.fromList(buffer.asTypedList(bytesRead));
    } finally {
      calloc.free(buffer);
    }
  }

  /// Read the entire file into a Uint8List.
  ///
  /// For large files, consider using [pread] with streaming.
  Uint8List readAll() {
    return read(_size, 0);
  }

  /// Zero-copy write: writes data directly from the provided buffer.
  /// returns number of bytes written, or -1 on error.
  int pwrite(Pointer<Uint8> buffer, int count, int offset) {
    _ensureOpen();
    return _bindings.nfs_pwrite(_context, _handle, buffer, count, offset);
  }

  /// Convenience write that takes a list of bytes.
  int write(List<int> bytes, int offset) {
    _ensureOpen();
    final count = bytes.length;
    final buffer = calloc<Uint8>(count);
    try {
      buffer.asTypedList(count).setAll(0, bytes);
      final bytesWritten = pwrite(buffer, count, offset);
      if (bytesWritten < 0) {
        throw NfsException('Write failed');
      }
      return bytesWritten;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Syncs data to disk
  void fsync() {
    _ensureOpen();
    final res = _bindings.nfs_fsync(_context, _handle);
    if (res != 0) {
      throw NfsException('fsync failed');
    }
  }

  /// Truncate file to specified length
  void truncate(int length) {
    _ensureOpen();
    final res = _bindings.nfs_ftruncate(_context, _handle, length);
    if (res != 0) {
      throw NfsException('ftruncate failed');
    }
  }

  /// Close the file handle.
  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _bindings.nfs_close(_context, _handle);
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('NfsFile has been closed');
    }
  }
}

/// Exception thrown by NFS operations
class NfsException implements Exception {
  final String message;

  NfsException(this.message);

  @override
  String toString() => 'NfsException: $message';
}
