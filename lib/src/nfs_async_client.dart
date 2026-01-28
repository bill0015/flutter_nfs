import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dart:ffi';
import 'nfs_client.dart';
import 'nfs_file.dart';

/// An asynchronous, isolate-encapsulated NFS client.
///
/// This client manages its own internal IO thread (Isolate) to ensure
/// responsiveness and thread safety. All operations return [Future].
class NfsClient {
  SendPort? _ioPort;
  final ReceivePort _responsePort = ReceivePort();
  Completer<void>? _initCompleter;

  // Map of request ID to Completer
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _requestIdCounter = 0;

  /// Initialize the internal IO isolate.
  Future<void> init() async {
    if (_ioPort != null) return;

    _initCompleter = Completer<void>();
    await Isolate.spawn(_nfsInternalWorker, _responsePort.sendPort);

    _responsePort.listen((message) {
      if (message is SendPort) {
        _ioPort = message;
        _initCompleter?.complete();
      } else if (message is Map) {
        final id = message['id'] as int;
        final completer = _pendingRequests.remove(id);
        if (completer != null) {
          if (message.containsKey('error')) {
            completer.completeError(message['error']);
          } else {
            completer.complete(message['result']);
          }
        }
      }
    });

    await _initCompleter!.future;
  }

  /// Mount an NFS share.
  Future<void> mount(String url) {
    return _sendRequest('mount', {'url': url});
  }

  /// Read a block of data from a file.
  /// Returns [Uint8List].
  Future<Uint8List> read(String path, int offset, int size) async {
    return await _sendRequest('read', {
      'path': path,
      'offset': offset,
      'size': size,
    }) as Uint8List;
  }

  /// Get file statistics (size).
  Future<int> stat(String path) async {
    return await _sendRequest('stat', {'path': path}) as int;
  }

  /// Check if file exists.
  Future<bool> exists(String path) async {
    return await _sendRequest('exists', {'path': path}) as bool;
  }

  /// List directory contents.
  /// Returns List of `Map<String, dynamic>` representing entries.
  /// (We return primitive maps to ensure isolate safety, wrapper can convert to NfsEntry if needed,
  /// but for now let's return `List<NfsEntry>` and handle serialization in worker).
  /// Wait, sending NfsEntry is fine if it's simple POJO.
  /// Let's return `List<NfsEntry>`.
  Future<List<NfsEntry>> listDir(String path) async {
    final result = await _sendRequest('listDir', {'path': path});
    // The result comes back as List<dynamic> (maps) likely if we serialize?
    // Or if NfsEntry is sendable (it is), we get List<NfsEntry>.
    // Isolate communication copies objects.
    return (result as List).cast<NfsEntry>();
  }

  /// Dispose the client and kill the worker isolate.
  void dispose() {
    _ioPort?.send({'cmd': 'dispose'});
    _responsePort.close();
    // Isolate kill handled by worker typically, or we can keep reference if needed.
    // Ideally worker exits on dispose cmd.
  }

  Future<dynamic> _sendRequest(String cmd, Map<String, dynamic> args) {
    if (_ioPort == null) throw StateError('NfsClient not initialized');

    final id = _requestIdCounter++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    _ioPort!.send({
      'cmd': cmd,
      'id': id,
      ...args,
    });

    return completer.future;
  }

  /// Write data to a file.
  Future<int> write(String path, Uint8List data, int offset) async {
    return await _sendRequest('write', {
      'path': path,
      'data': data,
      'offset': offset,
    }) as int;
  }

  /// Create a new empty file.
  Future<void> createFile(String path) async {
    await _sendRequest('createFile', {'path': path});
  }

  Future<void> delete(String path) async {
    await _sendRequest('delete', {'path': path});
  }

  Future<void> mkdir(String path) async {
    await _sendRequest('mkdir', {'path': path});
  }

  Future<void> rmdir(String path) async {
    await _sendRequest('rmdir', {'path': path});
  }

  Future<void> rename(String oldPath, String newPath) async {
    await _sendRequest('rename', {'oldPath': oldPath, 'newPath': newPath});
  }

  Future<void> truncate(String path, int length) async {
    await _sendRequest('truncate', {'path': path, 'length': length});
  }

  Future<void> chmod(String path, int mode) async {
    await _sendRequest('chmod', {'path': path, 'mode': mode});
  }

  Future<void> chown(String path, int uid, int gid) async {
    await _sendRequest('chown', {'path': path, 'uid': uid, 'gid': gid});
  }
}

// Internal Worker Entry Point
void _nfsInternalWorker(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  NfsNativeClient? client;
  // Cache open files to avoid re-opening per read?
  // Ideally yes. Map<Path, NfsFile>.
  final openFiles = <String, NfsFile>{};

  receivePort.listen((msg) {
    if (msg is! Map) return;

    final cmd = msg['cmd'];
    final id = msg['id'];

    try {
      if (cmd == 'dispose') {
        for (var f in openFiles.values) {
          f.close();
        }
        client?.dispose();
        receivePort.close();
        return;
      }

      // Lazy init client on first command if needed, or expected inside?
      // We init client wrapper here.
      client ??= NfsNativeClient();

      dynamic result;

      switch (cmd) {
        case 'mount':
          final url = msg['url'] as String;
          client!.mountSync(url);
          result = null;
          break;

        case 'read':
          final path = msg['path'] as String;
          final offset = msg['offset'] as int;
          final size = msg['size'] as int;

          NfsFile? file = openFiles[path];
          if (file == null) {
            file = client!.open(path);
            openFiles[path] = file;
          }

          // Allocate buffer
          final buffer = calloc<Uint8>(size);
          try {
            int read = file.pread(buffer, size, offset);
            if (read < 0) {
              throw NfsException('Read failed: ${client!.lastError}');
            }
            // Copy to Uint8List for transfer
            // Note: asTypedList view is invalid after free. We must copy.
            final bytes = Uint8List.fromList(buffer.asTypedList(read));
            result = bytes;
          } finally {
            calloc.free(buffer);
          }
          break;

        case 'stat':
          final path = msg['path'] as String;
          // Simple size check via open
          // Optimization: NfsClient should have `stat` method without open.
          // Currently `open` does stat.
          // Using open/close for stateless stat.
          // If we cache files, we can use cached handle stat?
          if (openFiles.containsKey(path)) {
            result = openFiles[path]!.size;
          } else {
            // Avoid caching purely for stat?
            final f = client!.open(path);
            result = f.size;
            f.close();
          }
          break;

        case 'exists':
          final path = msg['path'] as String;
          result = client!.exists(path);
          break;

        case 'write':
          final path = msg['path'] as String;
          final offset = msg['offset'] as int;
          final data = msg['data'] as Uint8List;

          NfsFile? file = openFiles[path];
          if (file == null) {
            // Open for writing (O_RDWR)
            file = client!.open(path, flags: 2); // O_RDWR = 2
            openFiles[path] = file;
          }

          result = file.write(data, offset);
          break;

        case 'createFile':
          final path = msg['path'] as String;
          final file = client!.createFile(path);
          // Cache the handle as it returns an open file
          openFiles[path] = file;
          result = null;
          break;

        case 'delete':
          client!.delete(msg['path'] as String);
          result = null;
          break;

        case 'mkdir':
          client!.mkdir(msg['path'] as String);
          result = null;
          break;

        case 'rmdir':
          client!.rmdir(msg['path'] as String);
          result = null;
          break;

        case 'rename':
          client!.rename(msg['oldPath'] as String, msg['newPath'] as String);
          result = null;
          break;

        case 'truncate':
          client!.truncate(msg['path'] as String, msg['length'] as int);
          result = null;
          break;

        case 'chmod':
          client!.chmod(msg['path'] as String, msg['mode'] as int);
          result = null;
          break;

        case 'chown':
          client!.chown(
              msg['path'] as String, msg['uid'] as int, msg['gid'] as int);
          result = null;
          break;

        case 'listDir':
          final path = msg['path'] as String;
          result = client!.listDir(path);
          break;

        default:
          throw StateError('Unknown command: $cmd');
      }

      if (id != null) {
        mainPort.send({
          'id': id,
          'result': result,
        });
      }
    } catch (e) {
      if (id != null) {
        mainPort.send({
          'id': id,
          'error': e.toString(),
        });
      }
    }
  });
}
