/*
 * nfs_bridge.c - Bridge to export libnfs functions for FFI
 *
 * CocoaPods links libnfs statically, but symbols need to be explicitly
 * exported for Dart FFI's DynamicLibrary.process() to find them.
 * This file wraps libnfs functions with __attribute__((visibility("default")))
 */

#include "nfs_bridge.h"
#include "nfsc/libnfs.h"

#if defined(__APPLE__) || defined(__GNUC__)
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Context management */
EXPORT struct nfs_context* bridge_nfs_init_context(void) {
    return nfs_init_context();
}

EXPORT void bridge_nfs_destroy_context(struct nfs_context* nfs) {
    nfs_destroy_context(nfs);
}

EXPORT char* bridge_nfs_get_error(struct nfs_context* nfs) {
    return nfs_get_error(nfs);
}

/* Mount operations */
EXPORT int bridge_nfs_mount(struct nfs_context* nfs, const char* server, const char* exportname) {
    return nfs_mount(nfs, server, exportname);
}

EXPORT int bridge_nfs_umount(struct nfs_context* nfs) {
    return nfs_umount(nfs);
}

/* URL parsing */
EXPORT struct nfs_url* bridge_nfs_parse_url_dir(struct nfs_context* nfs, const char* url) {
    return nfs_parse_url_dir(nfs, url);
}

EXPORT void bridge_nfs_destroy_url(struct nfs_url* url) {
    nfs_destroy_url(url);
}

/* File operations */
EXPORT int bridge_nfs_open(struct nfs_context* nfs, const char* path, int flags, struct nfsfh** nfsfh) {
    return nfs_open(nfs, path, flags, nfsfh);
}

EXPORT int bridge_nfs_close(struct nfs_context* nfs, struct nfsfh* nfsfh) {
    return nfs_close(nfs, nfsfh);
}

EXPORT int bridge_nfs_pread(struct nfs_context* nfs, struct nfsfh* nfsfh, void* buf, size_t count, uint64_t offset) {
    return nfs_pread(nfs, nfsfh, buf, count, offset);
}

EXPORT int bridge_nfs_fstat64(struct nfs_context* nfs, struct nfsfh* nfsfh, struct nfs_stat_64* st) {
    return nfs_fstat64(nfs, nfsfh, st);
}

EXPORT int bridge_nfs_pwrite(struct nfs_context* nfs, struct nfsfh* nfsfh, const void* buf, size_t count, uint64_t offset) {
    return nfs_pwrite(nfs, nfsfh, buf, count, offset);
}

EXPORT int bridge_nfs_fsync(struct nfs_context* nfs, struct nfsfh* nfsfh) {
    return nfs_fsync(nfs, nfsfh);
}

EXPORT int bridge_nfs_ftruncate(struct nfs_context* nfs, struct nfsfh* nfsfh, uint64_t length) {
    return nfs_ftruncate(nfs, nfsfh, length);
}

/* Management operations */
EXPORT int bridge_nfs_creat(struct nfs_context* nfs, const char* path, int mode, struct nfsfh** nfsfh) {
    return nfs_creat(nfs, path, mode, nfsfh);
}

EXPORT int bridge_nfs_unlink(struct nfs_context* nfs, const char* path) {
    return nfs_unlink(nfs, path);
}

EXPORT int bridge_nfs_mkdir(struct nfs_context* nfs, const char* path) {
    // nfs_mkdir takes primitive int mode usually
    return nfs_mkdir(nfs, path);
}

EXPORT int bridge_nfs_rmdir(struct nfs_context* nfs, const char* path) {
    return nfs_rmdir(nfs, path);
}

EXPORT int bridge_nfs_rename(struct nfs_context* nfs, const char* old_path, const char* new_path) {
    return nfs_rename(nfs, old_path, new_path);
}

EXPORT int bridge_nfs_truncate(struct nfs_context* nfs, const char* path, uint64_t length) {
    return nfs_truncate(nfs, path, length);
}

EXPORT int bridge_nfs_chmod(struct nfs_context* nfs, const char* path, int mode) {
    return nfs_chmod(nfs, path, mode);
}

EXPORT int bridge_nfs_chown(struct nfs_context* nfs, const char* path, int uid, int gid) {
    return nfs_chown(nfs, path, uid, gid);
}

/* Directory operations */
EXPORT int bridge_nfs_opendir(struct nfs_context* nfs, const char* path, struct nfsdir** nfsdir) {
    return nfs_opendir(nfs, path, nfsdir);
}

EXPORT struct nfsdirent* bridge_nfs_readdir(struct nfs_context* nfs, struct nfsdir* nfsdir) {
    return nfs_readdir(nfs, nfsdir);
}

EXPORT void bridge_nfs_closedir(struct nfs_context* nfs, struct nfsdir* nfsdir) {
    nfs_closedir(nfs, nfsdir);
}

/* Settings */
EXPORT void bridge_nfs_set_uid(struct nfs_context* nfs, int uid) {
    nfs_set_uid(nfs, uid);
}

EXPORT void bridge_nfs_set_gid(struct nfs_context* nfs, int gid) {
    nfs_set_gid(nfs, gid);
}

EXPORT int bridge_nfs_set_version(struct nfs_context* nfs, int version) {
    return nfs_set_version(nfs, version);
}

EXPORT void bridge_nfs_set_nfsport(struct nfs_context* nfs, int port) {
    nfs_set_nfsport(nfs, port);
}

EXPORT void bridge_nfs_set_mountport(struct nfs_context* nfs, int port) {
    nfs_set_mountport(nfs, port);
}

#ifdef __cplusplus
}
#endif
