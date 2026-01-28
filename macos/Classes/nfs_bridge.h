/*
 * nfs_bridge.h - Bridge header for libnfs FFI exports
 */

#ifndef NFS_BRIDGE_H
#define NFS_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#if defined(__APPLE__) || defined(__GNUC__)
#define EXPORT __attribute__((visibility("default")))
#else
#define EXPORT
#endif

/* Forward declarations */
struct nfs_context;
struct nfsfh;
struct nfsdir;
struct nfs_url;
struct nfs_stat_64;
struct nfsdirent;

#ifdef __cplusplus
extern "C" {
#endif

/* Context management */
EXPORT struct nfs_context* bridge_nfs_init_context(void);
EXPORT void bridge_nfs_destroy_context(struct nfs_context* nfs);
EXPORT char* bridge_nfs_get_error(struct nfs_context* nfs);

/* Mount operations */
EXPORT int bridge_nfs_mount(struct nfs_context* nfs, const char* server, const char* exportname);
EXPORT int bridge_nfs_umount(struct nfs_context* nfs);

/* URL parsing */
EXPORT struct nfs_url* bridge_nfs_parse_url_dir(struct nfs_context* nfs, const char* url);
EXPORT void bridge_nfs_destroy_url(struct nfs_url* url);

/* File operations */
EXPORT int bridge_nfs_open(struct nfs_context* nfs, const char* path, int flags, struct nfsfh** nfsfh);
EXPORT int bridge_nfs_close(struct nfs_context* nfs, struct nfsfh* nfsfh);
EXPORT int bridge_nfs_pread(struct nfs_context* nfs, struct nfsfh* nfsfh, void* buf, size_t count, uint64_t offset);
EXPORT int bridge_nfs_pwrite(struct nfs_context* nfs, struct nfsfh* nfsfh, const void* buf, size_t count, uint64_t offset);
EXPORT int bridge_nfs_fstat64(struct nfs_context* nfs, struct nfsfh* nfsfh, struct nfs_stat_64* st);
EXPORT int bridge_nfs_fsync(struct nfs_context* nfs, struct nfsfh* nfsfh);
EXPORT int bridge_nfs_ftruncate(struct nfs_context* nfs, struct nfsfh* nfsfh, uint64_t length);

/* Management operations */
EXPORT int bridge_nfs_creat(struct nfs_context* nfs, const char* path, int mode, struct nfsfh** nfsfh);
EXPORT int bridge_nfs_unlink(struct nfs_context* nfs, const char* path);
EXPORT int bridge_nfs_mkdir(struct nfs_context* nfs, const char* path);
EXPORT int bridge_nfs_rmdir(struct nfs_context* nfs, const char* path);
EXPORT int bridge_nfs_rename(struct nfs_context* nfs, const char* old_path, const char* new_path);
EXPORT int bridge_nfs_truncate(struct nfs_context* nfs, const char* path, uint64_t length);
EXPORT int bridge_nfs_chmod(struct nfs_context* nfs, const char* path, int mode);
EXPORT int bridge_nfs_chown(struct nfs_context* nfs, const char* path, int uid, int gid);

/* Directory operations */
EXPORT int bridge_nfs_opendir(struct nfs_context* nfs, const char* path, struct nfsdir** nfsdir);
EXPORT struct nfsdirent* bridge_nfs_readdir(struct nfs_context* nfs, struct nfsdir* nfsdir);
EXPORT void bridge_nfs_closedir(struct nfs_context* nfs, struct nfsdir* nfsdir);

/* Settings */
EXPORT void bridge_nfs_set_uid(struct nfs_context* nfs, int uid);
EXPORT void bridge_nfs_set_gid(struct nfs_context* nfs, int gid);
EXPORT int bridge_nfs_set_version(struct nfs_context* nfs, int version);
EXPORT void bridge_nfs_set_nfsport(struct nfs_context* nfs, int port);
EXPORT void bridge_nfs_set_mountport(struct nfs_context* nfs, int port);

#ifdef __cplusplus
}
#endif

#endif /* NFS_BRIDGE_H */
