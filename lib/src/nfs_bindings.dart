import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI bindings for libnfs via bridge functions
///
/// This provides low-level access to the libnfs C library functions.
class NfsBindings {
  static NfsBindings? _instance;
  late final DynamicLibrary _lib;

  // --- Function pointers ---

  // struct nfs_context *bridge_nfs_init_context(void);
  late final Pointer<NfsContext> Function() nfs_init_context;

  // void bridge_nfs_destroy_context(struct nfs_context *nfs);
  late final void Function(Pointer<NfsContext>) nfs_destroy_context;

  // int bridge_nfs_mount(struct nfs_context *nfs, const char *server, const char *exportname);
  late final int Function(Pointer<NfsContext>, Pointer<Utf8>, Pointer<Utf8>)
      nfs_mount;

  // int bridge_nfs_umount(struct nfs_context *nfs);
  late final int Function(Pointer<NfsContext>) nfs_umount;

  // int bridge_nfs_open(struct nfs_context *nfs, const char *path, int flags, struct nfsfh **nfsfh);
  late final int Function(
    Pointer<NfsContext>,
    Pointer<Utf8>,
    int,
    Pointer<Pointer<NfsFh>>,
  ) nfs_open;

  // int bridge_nfs_close(struct nfs_context *nfs, struct nfsfh *nfsfh);
  late final int Function(Pointer<NfsContext>, Pointer<NfsFh>) nfs_close;

  // int bridge_nfs_pread(struct nfs_context *nfs, struct nfsfh *nfsfh, void *buf, size_t count, uint64_t offset);
  late final int Function(
    Pointer<NfsContext>,
    Pointer<NfsFh>,
    Pointer<Uint8>,
    int,
    int,
  ) nfs_pread;

  // int bridge_nfs_fstat64(struct nfs_context *nfs, struct nfsfh *nfsfh, struct nfs_stat_64 *st);
  late final int Function(
    Pointer<NfsContext>,
    Pointer<NfsFh>,
    Pointer<NfsStat64>,
  ) nfs_fstat64;

  // int bridge_nfs_opendir(struct nfs_context *nfs, const char *path, struct nfsdir **nfsdir);
  late final int Function(
    Pointer<NfsContext>,
    Pointer<Utf8>,
    Pointer<Pointer<NfsDir>>,
  ) nfs_opendir;

  // struct nfsdirent *bridge_nfs_readdir(struct nfs_context *nfs, struct nfsdir *nfsdir);
  late final Pointer<NfsDirent> Function(Pointer<NfsContext>, Pointer<NfsDir>)
      nfs_readdir;

  // void bridge_nfs_closedir(struct nfs_context *nfs, struct nfsdir *nfsdir);
  late final void Function(Pointer<NfsContext>, Pointer<NfsDir>) nfs_closedir;

  // char *bridge_nfs_get_error(struct nfs_context *nfs);
  late final Pointer<Utf8> Function(Pointer<NfsContext>) nfs_get_error;

  // struct nfs_url *bridge_nfs_parse_url_dir(struct nfs_context *nfs, const char *url);
  late final Pointer<NfsUrl> Function(Pointer<NfsContext>, Pointer<Utf8>)
      nfs_parse_url_dir;

  // void bridge_nfs_destroy_url(struct nfs_url *url);
  late final void Function(Pointer<NfsUrl>) nfs_destroy_url;

  // --- Write & Management Operations ---

  // int bridge_nfs_pwrite(struct nfs_context *nfs, struct nfsfh *nfsfh, const void *buf, size_t count, uint64_t offset);
  late final int Function(
    Pointer<NfsContext>,
    Pointer<NfsFh>,
    Pointer<Uint8>,
    int,
    int,
  ) nfs_pwrite;

  // int bridge_nfs_fsync(struct nfs_context *nfs, struct nfsfh *nfsfh);
  late final int Function(Pointer<NfsContext>, Pointer<NfsFh>) nfs_fsync;

  // int bridge_nfs_ftruncate(struct nfs_context *nfs, struct nfsfh *nfsfh, uint64_t length);
  late final int Function(Pointer<NfsContext>, Pointer<NfsFh>, int)
      nfs_ftruncate;

  // int bridge_nfs_creat(struct nfs_context *nfs, const char *path, int mode, struct nfsfh **nfsfh);
  late final int Function(
    Pointer<NfsContext>,
    Pointer<Utf8>,
    int,
    Pointer<Pointer<NfsFh>>,
  ) nfs_creat;

  // int bridge_nfs_unlink(struct nfs_context *nfs, const char *path);
  late final int Function(Pointer<NfsContext>, Pointer<Utf8>) nfs_unlink;

  // int bridge_nfs_mkdir(struct nfs_context *nfs, const char *path);
  late final int Function(Pointer<NfsContext>, Pointer<Utf8>) nfs_mkdir;

  // int bridge_nfs_rmdir(struct nfs_context *nfs, const char *path);
  late final int Function(Pointer<NfsContext>, Pointer<Utf8>) nfs_rmdir;

  // int bridge_nfs_rename(struct nfs_context *nfs, const char *old_path, const char *new_path);
  late final int Function(Pointer<NfsContext>, Pointer<Utf8>, Pointer<Utf8>)
      nfs_rename;

  // int bridge_nfs_truncate(struct nfs_context *nfs, const char *path, uint64_t length);
  late final int Function(Pointer<NfsContext>, Pointer<Utf8>, int) nfs_truncate;

  // int bridge_nfs_chmod(struct nfs_context *nfs, const char *path, int mode);
  late final int Function(Pointer<NfsContext>, Pointer<Utf8>, int) nfs_chmod;

  // int bridge_nfs_chown(struct nfs_context *nfs, const char *path, int uid, int gid);
  late final int Function(Pointer<NfsContext>, Pointer<Utf8>, int, int)
      nfs_chown;

  // void nfs_vfs_add_path_hint(const char* full_url, const char* server, const char* export_path, const char* relative_path)
  void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)?
      nfs_vfs_add_path_hint;

  NfsBindings._() {
    _lib = _loadLibrary();
    _bindFunctions();
  }

  factory NfsBindings() {
    return _instance ??= NfsBindings._();
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libflutter_nfs.so');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.open('flutter_nfs.framework/flutter_nfs');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('flutter_nfs.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libflutter_nfs.so');
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }

  void _bindFunctions() {
    nfs_init_context = _lib
        .lookup<NativeFunction<Pointer<NfsContext> Function()>>(
          'bridge_nfs_init_context',
        )
        .asFunction();

    nfs_destroy_context = _lib
        .lookup<NativeFunction<Void Function(Pointer<NfsContext>)>>(
          'bridge_nfs_destroy_context',
        )
        .asFunction();

    nfs_mount = _lib
        .lookup<
            NativeFunction<
                Int32 Function(Pointer<NfsContext>, Pointer<Utf8>,
                    Pointer<Utf8>)>>('bridge_nfs_mount')
        .asFunction();

    nfs_umount = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<NfsContext>)>>(
          'bridge_nfs_umount',
        )
        .asFunction();

    nfs_open = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<NfsContext>,
                  Pointer<Utf8>,
                  Int32,
                  Pointer<Pointer<NfsFh>>,
                )>>('bridge_nfs_open')
        .asFunction();

    nfs_close = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<NfsContext>, Pointer<NfsFh>)>>('bridge_nfs_close')
        .asFunction();

    nfs_pread = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<NfsContext>,
                  Pointer<NfsFh>,
                  Pointer<Uint8>,
                  Size,
                  Uint64,
                )>>('bridge_nfs_pread')
        .asFunction();

    nfs_fstat64 = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<NfsContext>,
                  Pointer<NfsFh>,
                  Pointer<NfsStat64>,
                )>>('bridge_nfs_fstat64')
        .asFunction();

    nfs_opendir = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<NfsContext>,
                  Pointer<Utf8>,
                  Pointer<Pointer<NfsDir>>,
                )>>('bridge_nfs_opendir')
        .asFunction();

    nfs_readdir = _lib
        .lookup<
            NativeFunction<
                Pointer<NfsDirent> Function(Pointer<NfsContext>,
                    Pointer<NfsDir>)>>('bridge_nfs_readdir')
        .asFunction();

    nfs_closedir = _lib
        .lookup<
            NativeFunction<
                Void Function(Pointer<NfsContext>,
                    Pointer<NfsDir>)>>('bridge_nfs_closedir')
        .asFunction();

    nfs_get_error = _lib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<NfsContext>)>>(
          'bridge_nfs_get_error',
        )
        .asFunction();

    nfs_parse_url_dir = _lib
        .lookup<
            NativeFunction<
                Pointer<NfsUrl> Function(Pointer<NfsContext>,
                    Pointer<Utf8>)>>('bridge_nfs_parse_url_dir')
        .asFunction();

    nfs_destroy_url = _lib
        .lookup<NativeFunction<Void Function(Pointer<NfsUrl>)>>(
          'bridge_nfs_destroy_url',
        )
        .asFunction();

    // --- Write & Management Enpoint Bindings ---
    nfs_pwrite = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                  Pointer<NfsContext>,
                  Pointer<NfsFh>,
                  Pointer<Uint8>, // const void* in C, effectively just bytes
                  Size,
                  Uint64,
                )>>('bridge_nfs_pwrite')
        .asFunction();

    nfs_fsync = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<NfsContext>, Pointer<NfsFh>)>>('bridge_nfs_fsync')
        .asFunction();

    nfs_ftruncate = _lib
        .lookup<
            NativeFunction<
                Int32 Function(Pointer<NfsContext>, Pointer<NfsFh>,
                    Uint64)>>('bridge_nfs_ftruncate')
        .asFunction();

    nfs_creat = _lib
        .lookup<
            NativeFunction<
                Int32 Function(Pointer<NfsContext>, Pointer<Utf8>, Int32,
                    Pointer<Pointer<NfsFh>>)>>('bridge_nfs_creat')
        .asFunction();

    nfs_unlink = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<NfsContext>, Pointer<Utf8>)>>('bridge_nfs_unlink')
        .asFunction();

    nfs_mkdir = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<NfsContext>, Pointer<Utf8>)>>('bridge_nfs_mkdir')
        .asFunction();

    nfs_rmdir = _lib
        .lookup<
            NativeFunction<
                Int32 Function(
                    Pointer<NfsContext>, Pointer<Utf8>)>>('bridge_nfs_rmdir')
        .asFunction();

    nfs_rename = _lib
        .lookup<
            NativeFunction<
                Int32 Function(Pointer<NfsContext>, Pointer<Utf8>,
                    Pointer<Utf8>)>>('bridge_nfs_rename')
        .asFunction();

    nfs_truncate = _lib
        .lookup<
            NativeFunction<
                Int32 Function(Pointer<NfsContext>, Pointer<Utf8>,
                    Uint64)>>('bridge_nfs_truncate')
        .asFunction();

    nfs_chmod = _lib
        .lookup<
            NativeFunction<
                Int32 Function(Pointer<NfsContext>, Pointer<Utf8>,
                    Int32)>>('bridge_nfs_chmod')
        .asFunction();

    nfs_chown = _lib
        .lookup<
            NativeFunction<
                Int32 Function(Pointer<NfsContext>, Pointer<Utf8>, Int32,
                    Int32)>>('bridge_nfs_chown')
        .asFunction();

    // --- Optional Cache/VFS API ---
    void bindOptional(String name, Function(DynamicLibrary) binder) {
      try {
        binder(_lib);
      } catch (e) {
        print('[NfsBindings] Optional symbol not found: $name');
      }
    }

    bindOptional('cache_init', (lib) {
      cache_init = lib
          .lookup<NativeFunction<Void Function(Int32)>>('cache_init')
          .asFunction();
    });
    bindOptional('cache_read', (lib) {
      cache_read = lib
          .lookup<
              NativeFunction<
                  Int32 Function(Uint64, Int32, Pointer<Uint8>)>>('cache_read')
          .asFunction();
    });
    bindOptional('cache_put', (lib) {
      cache_put = lib
          .lookup<NativeFunction<Void Function(Uint64, Pointer<Uint8>, Int32)>>(
              'cache_put')
          .asFunction();
    });
    bindOptional('cache_has_block', (lib) {
      cache_has_block = lib
          .lookup<NativeFunction<Int32 Function(Uint64)>>('cache_has_block')
          .asFunction();
    });
    bindOptional('cache_get_block_size', (lib) {
      cache_get_block_size = lib
          .lookup<NativeFunction<Int32 Function()>>('cache_get_block_size')
          .asFunction();
    });
    bindOptional('get_libretro_vfs', (lib) {
      get_libretro_vfs = lib
          .lookup<NativeFunction<Pointer<Void> Function()>>('get_libretro_vfs')
          .asFunction();
    });
    bindOptional('bridge_fill_vfs_info', (lib) {
      bridge_fill_vfs_info = lib
          .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
              'bridge_fill_vfs_info')
          .asFunction();
    });
    bindOptional('nfs_set_prefetch_callback', (lib) {
      nfs_set_prefetch_callback = lib
          .lookup<
                  NativeFunction<
                      Void Function(
                          Pointer<NativeFunction<Void Function(Uint64)>>)>>(
              'nfs_set_prefetch_callback')
          .asFunction();
    });
    bindOptional('nfs_set_log_callback', (lib) {
      nfs_set_log_callback = lib
          .lookup<
                  NativeFunction<
                      Void Function(
                          Pointer<NativeFunction<DartLogCallbackNative>>)>>(
              'nfs_set_log_callback')
          .asFunction();
    });
    bindOptional('nfs_vfs_add_path_hint', (lib) {
      nfs_vfs_add_path_hint = lib
          .lookup<
              NativeFunction<
                  Void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>,
                      Pointer<Utf8>)>>('nfs_vfs_add_path_hint')
          .asFunction();
    });
  }

  // --- Cache API ---
  void Function(int)? cache_init;
  int Function(int, int, Pointer<Uint8>)? cache_read;
  void Function(int, Pointer<Uint8>, int)? cache_put;
  int Function(int)? cache_has_block;
  int Function()? cache_get_block_size;

  // --- VFS API ---
  Pointer<Void> Function()? get_libretro_vfs;
  void Function(Pointer<Void>, Pointer<Void>)? bridge_fill_vfs_info;
  void Function(Pointer<NativeFunction<Void Function(Uint64)>>)?
      nfs_set_prefetch_callback;
  void Function(Pointer<NativeFunction<DartLogCallbackNative>>)?
      nfs_set_log_callback;
}

typedef DartLogCallbackNative = Void Function(
    Int32 level, Pointer<Utf8> message);

// --- Opaque Structs ---

/// Opaque NFS context handle
final class NfsContext extends Opaque {}

/// Opaque NFS file handle
final class NfsFh extends Opaque {}

/// Opaque NFS directory handle
final class NfsDir extends Opaque {}

/// NFS URL struct
final class NfsUrl extends Struct {
  external Pointer<Utf8> server;

  @Int32()
  external int port;

  external Pointer<Utf8> path;

  external Pointer<Utf8> file;
}

/// NFS stat structure (64-bit)
final class NfsStat64 extends Struct {
  @Uint64()
  external int nfs_dev;

  @Uint64()
  external int nfs_ino;

  @Uint64()
  external int nfs_mode;

  @Uint64()
  external int nfs_nlink;

  @Uint64()
  external int nfs_uid;

  @Uint64()
  external int nfs_gid;

  @Uint64()
  external int nfs_rdev;

  @Uint64()
  external int nfs_size;

  @Uint64()
  external int nfs_blksize;

  @Uint64()
  external int nfs_blocks;

  @Uint64()
  external int nfs_atime;

  @Uint64()
  external int nfs_mtime;

  @Uint64()
  external int nfs_ctime;

  @Uint64()
  external int nfs_atime_nsec;

  @Uint64()
  external int nfs_mtime_nsec;

  @Uint64()
  external int nfs_ctime_nsec;

  @Uint64()
  external int nfs_used;
}

/// NFS directory entry
final class NfsDirent extends Struct {
  external Pointer<NfsDirent> next;

  external Pointer<Utf8> name;

  @Uint64()
  external int inode;

  @Uint32()
  external int type;

  @Uint32()
  external int mode;

  @Uint64()
  external int size;

  @Uint64()
  external int atime;

  @Uint64()
  external int mtime;

  @Uint64()
  external int ctime;

  @Uint32()
  external int uid;

  @Uint32()
  external int gid;

  @Uint32()
  external int nlink;

  @Uint64()
  external int dev;

  @Uint64()
  external int rdev;

  @Uint64()
  external int blksize;

  @Uint64()
  external int blocks;

  @Uint64()
  external int used;
}

// File open flags (from fcntl.h)
// ignore: constant_identifier_names
const int O_RDONLY = 0;
// ignore: constant_identifier_names
const int O_WRONLY = 1;
// ignore: constant_identifier_names
const int O_RDWR = 2;
