import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'nfs_client.dart';
import 'nfs_file.dart';

/// Worker isolate for NFS prefetching and cache maintenance
class NfsWorker {
  SendPort? _sendPort;
  Isolate? _isolate;
  final String nfsUrl;
  final String filePath;

  NfsWorker({required this.nfsUrl, required this.filePath});

  Future<void> start() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_workerEntryPoint, [
      receivePort.sendPort,
      nfsUrl,
      filePath,
    ]);
    _sendPort = await receivePort.first as SendPort;
  }

  void stop() {
    _sendPort?.send({'cmd': 'stop'});
    _isolate?.kill();
    _isolate = null;
  }

  static void _workerEntryPoint(List<dynamic> args) {
    SendPort mainSendPort = args[0];
    String url = args[1];
    String path = args[2];
    ReceivePort port = ReceivePort();
    mainSendPort.send(port.sendPort);

    NfsNativeClient? client;
    NfsFile? file;
    Pointer<Uint8>? buffer;
    int blockSize = 128 * 1024;
    // Keep reference to callable to prevent GC
    NativeCallable<Void Function(Uint64)>? prefetchCallback;

    try {
      client = NfsNativeClient();
      client.mountSync(url);

      // Provide path hint for mount URL
      try {
        final mountParsed = client.parseUrl(url);
        client.addPathHint(
            url, mountParsed.server, mountParsed.path, mountParsed.file);

        // Provide path hint for full file URL
        String fullFileUrl = url;
        if (!fullFileUrl.endsWith('/') && !path.startsWith('/')) {
          fullFileUrl += '/';
        }
        fullFileUrl += path;

        // If the path contains multiple segments, we want the final parsed result
        // but often the VFS requests the exact full URL string it was given.
        final fileParsed = client.parseUrl(fullFileUrl);
        client.addPathHint(
            fullFileUrl, fileParsed.server, fileParsed.path, fileParsed.file);
      } catch (e) {
        print('[NfsWorker] Failed to provide path hints: $e');
      }

      // Open the file
      try {
        file = client.open(path);
      } catch (e) {
        print('[NfsWorker] Failed to open file: $path Error: $e');
        return;
      }

      buffer = calloc<Uint8>(blockSize);
      int fileSize = file.size;

      // Create C++ -> Dart Callback
      // When C++ VFS reads block N, it calls this with N+1
      prefetchCallback =
          NativeCallable<Void Function(Uint64)>.listener((int blockId) {
        _prefetchBlocks(blockId, client!, file!, buffer!, blockSize, fileSize);
      });

      // Register callback with C++ layer
      if (client.bindings.nfs_set_prefetch_callback != null) {
        client.bindings
            .nfs_set_prefetch_callback!(prefetchCallback.nativeFunction);
        print('[NfsWorker] Prefetch callback registered');
      } else {
        print(
            '[NfsWorker] Warning: nfs_set_prefetch_callback not available. Prefetching disabled.');
      }

      port.listen((msg) {
        if (msg is Map) {
          if (msg['cmd'] == 'stop') {
            if (prefetchCallback != null) {
              // Unregister? optional
              prefetchCallback.close();
            }
            port.close();
            calloc.free(buffer!);
            file?.close();
            client?.dispose();
            return;
          }
        }
      });
    } catch (e) {
      print('[NfsWorker] Error: $e');
      if (buffer != null) calloc.free(buffer);
      file?.close();
      client?.dispose();
      prefetchCallback?.close();
    }
  }

  static void _prefetchBlocks(int startBlockId, NfsNativeClient client,
      NfsFile file, Pointer<Uint8> buffer, int blockSize, int fileSize) {
    if (client.bindings.cache_has_block == null ||
        client.bindings.cache_put == null) {
      return;
    }

    // Prefetch this block and next 2 blocks
    for (int i = 0; i < 3; i++) {
      int targetBlock = startBlockId + i;

      if (client.bindings.cache_has_block!(targetBlock) != 0) {
        continue; // Already in cache
      }

      int targetOffset = targetBlock * blockSize;
      if (targetOffset >= fileSize) break;

      int readSize = (targetOffset + blockSize > fileSize)
          ? fileSize - targetOffset
          : blockSize;

      // Read from NFS (Blocking call in this isolate)
      int bytes = file.pread(buffer, readSize, targetOffset);
      if (bytes > 0) {
        // Push to shared C++ Cache
        client.bindings.cache_put!(targetBlock, buffer, bytes);
      }
    }
  }
}
