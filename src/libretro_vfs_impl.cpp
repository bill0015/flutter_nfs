#include "libretro_defines.h"
#include "block_cache.hpp"
#include "nfs_pool.hpp"
#include <nfsc/libnfs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <iostream>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <mutex>
#include <sys/stat.h>

// Callback to notify Dart
typedef void (*PrefetchCallback)(uint64_t block_id);
static PrefetchCallback g_prefetch_callback = nullptr;

#if defined(__APPLE__) || defined(__GNUC__)
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define EXPORT
#endif

extern "C" {
    EXPORT void nfs_set_prefetch_callback(PrefetchCallback cb) {
        g_prefetch_callback = cb;
    }
}

// Helper: Simple URL encode for spaces
static std::string url_encode_spaces(const std::string& input) {
    std::string output = "";
    for (char c : input) {
        if (c == ' ') output += "%20";
        else output += c;
    }
    return output;
}

struct RetroNfsFile {
    struct nfs_context *nfs;
    struct nfsfh *fh;
    std::mutex* context_mutex; 
    uint64_t offset;
    uint64_t size;
};

// --- VFS Implementation ---

static const char *retro_vfs_get_path(struct retro_vfs_file_handle *stream) {
    return "nfs_file";
}

static struct retro_vfs_file_handle *retro_vfs_open(const char *path, unsigned mode, unsigned hints) {
    fprintf(stderr, "[LibretroVFS] retro_vfs_open: path=%s, mode=%u\n", path ? path : "NULL", mode);
    fflush(stderr);

    if (!path || strncmp(path, "nfs://", 6) != 0) {
        fprintf(stderr, "[LibretroVFS] Invalid path skip: %s\n", path ? path : "NULL");
        fflush(stderr);
        return NULL;
    }

    std::string encoded_path = url_encode_spaces(path);

    struct nfs_context *nfs_tmp = nfs_init_context();
    if (!nfs_tmp) return NULL;

    struct nfs_url *url = nfs_parse_url_dir(nfs_tmp, encoded_path.c_str());
    if (!url) {
        fprintf(stderr, "[LibretroVFS] Failed to parse URL: %s\n", encoded_path.c_str());
        nfs_destroy_context(nfs_tmp);
        return NULL;
    }

    NfsPool::ConnectionHandle handle = NfsPool::instance().acquire(url->server, url->path);
    
    std::string filename = "";
    if (url->file) {
        filename = url->file;
    } else {
        printf("[LibretroVFS] Warning: url->file is NULL for %s\n", encoded_path.c_str());
    }
    nfs_destroy_url(url);
    nfs_destroy_context(nfs_tmp);

    if (!handle.nfs) {
        printf("[LibretroVFS] Failed to acquire NFS connection\n");
        fflush(stdout);
        return NULL;
    }

    struct nfsfh *fh = NULL;
    int flags = (mode & RETRO_VFS_FILE_ACCESS_WRITE) ? (O_RDWR | O_CREAT) : O_RDONLY;
    
    {
        std::lock_guard<std::mutex> lock(*handle.mutex);
        if (nfs_open(handle.nfs, filename.c_str(), flags, &fh) != 0) {
            fprintf(stderr, "[LibretroVFS] Failed to open file: %s (Error: %s)\n", 
                    filename.c_str(), nfs_get_error(handle.nfs));
            fflush(stderr);
            NfsPool::instance().release(handle.nfs);
            return NULL;
        }
    }

    RetroNfsFile* file = new RetroNfsFile();
    file->nfs = handle.nfs;
    file->fh = fh;
    file->context_mutex = handle.mutex;
    file->offset = 0;
    
    struct nfs_stat_64 st;
    {
        std::lock_guard<std::mutex> lock(*file->context_mutex);
        if (nfs_fstat64(file->nfs, fh, &st) == 0) {
            file->size = st.nfs_size;
        } else {
            file->size = 0;
        }
    }

    printf("[LibretroVFS] Successfully opened %s (Size: %llu)\n", filename.c_str(), file->size);
    fflush(stdout);
    return (struct retro_vfs_file_handle*)file;
}

static int retro_vfs_close(struct retro_vfs_file_handle *stream) {
    if (!stream) return -1;
    RetroNfsFile* file = (RetroNfsFile*)stream;
    if (file) {
        if (file->fh) {
            std::lock_guard<std::mutex> lock(*file->context_mutex);
            nfs_close(file->nfs, file->fh);
        }
        if (file->nfs) NfsPool::instance().release(file->nfs);
        delete file;
    }
    return 0;
}

static int64_t retro_vfs_size(struct retro_vfs_file_handle *stream) {
    if (!stream) return -1;
    RetroNfsFile* file = (RetroNfsFile*)stream;
    return (int64_t)file->size;
}

static int64_t retro_vfs_tell(struct retro_vfs_file_handle *stream) {
    if (!stream) return -1;
    RetroNfsFile* file = (RetroNfsFile*)stream;
    return (int64_t)file->offset;
}

static int64_t retro_vfs_seek(struct retro_vfs_file_handle *stream, int64_t offset, int seek_position) {
    if (!stream) return -1;
    RetroNfsFile* file = (RetroNfsFile*)stream;
    int64_t target_offset = (int64_t)file->offset;

    switch (seek_position) {
        case RETRO_VFS_SEEK_POSITION_START:   target_offset = offset; break;
        case RETRO_VFS_SEEK_POSITION_CURRENT: target_offset += offset; break;
        case RETRO_VFS_SEEK_POSITION_END:     target_offset = (int64_t)file->size + offset; break;
    }

    if (target_offset < 0) target_offset = 0;
    if (target_offset > (int64_t)file->size) target_offset = (int64_t)file->size;

    file->offset = (uint64_t)target_offset;
    return (int64_t)file->offset;
}

static int64_t retro_vfs_read(struct retro_vfs_file_handle *stream, void *s, uint64_t len) {
    if (!stream || !s) return -1;
    RetroNfsFile* file = (RetroNfsFile*)stream;
    uint8_t* buf = (uint8_t*)s;
    uint64_t block_id = file->offset / BLOCK_SIZE;
    
    int bytes = BlockCache::instance().read(file->offset, len, buf);
    if (g_prefetch_callback) {
        g_prefetch_callback(block_id);
        g_prefetch_callback(block_id + 1);
        g_prefetch_callback(block_id + 2);
    }

    if (bytes > 0) {
        file->offset += bytes;
        return bytes;
    }
    
    int retry = 4;
    while (retry-- > 0) {
        usleep(1000);
        bytes = BlockCache::instance().read(file->offset, len, buf);
        if (bytes > 0) {
            file->offset += bytes;
            return bytes;
        }
    }

    // 2. Cache Miss: Sync Fallback
    int res = 0;
    {
        std::lock_guard<std::mutex> lock(*file->context_mutex);
        res = nfs_pread(file->nfs, file->fh, buf, len, file->offset);
        if (res > 0) {
            fprintf(stderr, "[LibretroVFS] Sync PREAD SUCCESS: offset=%llu, request_len=%llu, actual_len=%d\n", file->offset, len, res);
            fflush(stderr);
            file->offset += res;
        } else if (res < 0) {
            fprintf(stderr, "[LibretroVFS] Sync PREAD FAILED: offset=%llu, error=%s\n", file->offset, nfs_get_error(file->nfs));
            fflush(stderr);
        }
    }
    return (int64_t)res;
}

static int64_t retro_vfs_write(struct retro_vfs_file_handle *stream, const void *s, uint64_t len) {
    RetroNfsFile* file = (RetroNfsFile*)stream;
    int res = 0;
    {
        std::lock_guard<std::mutex> lock(*file->context_mutex);
        res = nfs_pwrite(file->nfs, file->fh, (void*)s, len, file->offset);
    }
    if (res > 0) file->offset += res;
    return res;
}

static int retro_vfs_flush(struct retro_vfs_file_handle *stream) { return 0; }
static int retro_vfs_remove(const char *path) { return -1; }
static int retro_vfs_rename(const char *old_path, const char *new_path) { return -1; }

static int64_t retro_vfs_truncate(struct retro_vfs_file_handle *stream, int64_t length) { return -1; }

static int retro_vfs_stat(const char *path, int32_t *size) {
    if (!path || strncmp(path, "nfs://", 6) != 0) return 0;
    
    std::string encoded_path = url_encode_spaces(path);
    struct nfs_context *nfs_tmp = nfs_init_context();
    fprintf(stderr, "[LibretroVfs] retro_vfs_stat: path=%s\n", path);
    fflush(stderr);

    struct nfs_url *url = nfs_parse_url_dir(nfs_tmp, encoded_path.c_str());
    if (!url) {
        nfs_destroy_context(nfs_tmp);
        return 0;
    }

    NfsPool::ConnectionHandle handle = NfsPool::instance().acquire(url->server, url->path);
    std::string filename = url->file;
    nfs_destroy_url(url);
    nfs_destroy_context(nfs_tmp);

    if (!handle.nfs) return 0;

    struct nfs_stat_64 st;
    int res = 0;
    {
        std::lock_guard<std::mutex> lock(*handle.mutex);
        if (nfs_stat64(handle.nfs, filename.c_str(), &st) == 0) {
            res |= RETRO_VFS_STAT_IS_VALID;
            if (size) *size = (int32_t)st.nfs_size;
            if (S_ISDIR(st.nfs_mode)) res |= RETRO_VFS_STAT_IS_DIRECTORY;
        }
    }
    NfsPool::instance().release(handle.nfs);
    fprintf(stderr, "[LibretroVfs] retro_vfs_stat return: %d, size_reported=%d\n", res, (size ? *size : -1));
    fflush(stderr);
    return res;
}

static int retro_vfs_mkdir(const char *dir) { return -1; }
static struct retro_vfs_dir_handle *retro_vfs_opendir(const char *dir, bool include_hidden) { return NULL; }
static bool retro_vfs_readdir(struct retro_vfs_dir_handle *dhandle) { return false; }
static const char *retro_vfs_dirent_get_name(struct retro_vfs_dir_handle *dhandle) { return NULL; }
static bool retro_vfs_dirent_is_dir(struct retro_vfs_dir_handle *dhandle) { return false; }
static int retro_vfs_closedir(struct retro_vfs_dir_handle *dhandle) { return -1; }

static struct retro_vfs_interface g_nfs_vfs = {
    retro_vfs_get_path,
    retro_vfs_open,
    retro_vfs_close,
    retro_vfs_size,
    retro_vfs_tell,
    retro_vfs_seek,
    retro_vfs_read,
    retro_vfs_write,
    retro_vfs_flush,
    retro_vfs_remove,
    retro_vfs_rename,
    retro_vfs_truncate,
    retro_vfs_stat,
    retro_vfs_mkdir,
    retro_vfs_opendir,
    retro_vfs_readdir,
    retro_vfs_dirent_get_name,
    retro_vfs_dirent_is_dir,
    retro_vfs_closedir,
};

extern "C" {
    EXPORT struct retro_vfs_interface* get_libretro_vfs() {
        return &g_nfs_vfs;
    }
}
