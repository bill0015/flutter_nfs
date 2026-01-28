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
#include <stdarg.h>

// Callback to notify Dart
typedef void (*PrefetchCallback)(uint64_t block_id);
static PrefetchCallback g_prefetch_callback = nullptr;

typedef void (*DartLogCallback)(int level, const char* message);
static DartLogCallback g_dart_log_callback = nullptr;

// Path Hint Cache to avoid blocking URL parsing in open
struct PathHint {
    std::string server;
    std::string export_path;
    std::string relative_path;
};
static std::mutex g_hint_mutex;
static std::unordered_map<std::string, PathHint> g_path_hints;

#if defined(__APPLE__) || defined(__GNUC__)
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define EXPORT
#endif

static void libretro_log_bridge(enum retro_log_level level, const char *fmt, ...);

extern "C" {
    EXPORT void nfs_set_prefetch_callback(PrefetchCallback cb) {
        g_prefetch_callback = cb;
    }

    EXPORT retro_log_printf_t get_log_callback_bridge() {
        return libretro_log_bridge;
    }

    EXPORT void nfs_set_log_callback(DartLogCallback cb) {
        g_dart_log_callback = cb;
    }

    EXPORT void nfs_vfs_add_path_hint(const char* full_url, const char* server, const char* export_path, const char* relative_path) {
        if (!full_url || !server || !export_path || !relative_path) return;
        std::lock_guard<std::mutex> lock(g_hint_mutex);
        PathHint hint = {server, export_path, relative_path};
        g_path_hints[full_url] = hint;
        printf("[LibretroVFS] Added path hint for %s (Server: %s, Export: %s, Path: %s)\n", 
                full_url, server, export_path, relative_path);
        fflush(stdout);
    }
}

static void libretro_log_bridge(enum retro_log_level level, const char *fmt, ...) {
    if (!g_dart_log_callback) return;
    
    char buf[4096];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    g_dart_log_callback((int)level, buf);
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
    printf("[LibretroVFS] ========================================\n");
    printf("[LibretroVFS] retro_vfs_open CALLED\n");
    printf("[LibretroVFS]   path: %s\n", path ? path : "NULL");
    printf("[LibretroVFS]   mode: %u, hints: %u\n", mode, hints);
    printf("[LibretroVFS] ========================================\n");
    fflush(stdout);

    if (!path) {
        printf("[LibretroVFS] ERROR: path is NULL, returning NULL\n");
        fflush(stdout);
        return NULL;
    }
    
    if (strncmp(path, "nfs://", 6) != 0) {
        printf("[LibretroVFS] NOT an NFS path (prefix check failed), returning NULL to fallback\n");
        printf("[LibretroVFS] First 10 chars: %.10s\n", path);
        fflush(stdout);
        return NULL;
    }
    
    printf("[LibretroVFS] Path IS NFS, proceeding with NFS open...\n");
    fflush(stdout);

    std::string server, export_path, filename;
    bool found_hint = false;

    {
        std::lock_guard<std::mutex> lock(g_hint_mutex);
        if (g_path_hints.count(path)) {
            const auto& hint = g_path_hints[path];
            server = hint.server;
            export_path = hint.export_path;
            filename = hint.relative_path;
            found_hint = true;
            printf("[LibretroVFS] Hint FOUND for %s -> Server: %s, Export: %s, File: %s\n", 
                    path, server.c_str(), export_path.c_str(), filename.c_str());
            fflush(stdout);
        }
    }

    if (!found_hint) {
        // Fallback to slow parsing if no hint provided
        struct nfs_context *nfs_tmp = nfs_init_context();
        if (!nfs_tmp) return NULL;

        struct nfs_url *url = nfs_parse_url_dir(nfs_tmp, path);
        if (!url) {
            printf("[LibretroVFS] Failed to parse URL and no hint found: %s\n", path);
            fflush(stdout);
            nfs_destroy_context(nfs_tmp);
            return NULL;
        }
        server = url->server;
        export_path = url->path;
        if (url->file) filename = url->file;
        nfs_destroy_url(url);
        nfs_destroy_context(nfs_tmp);
    }

    NfsPool::ConnectionHandle handle = NfsPool::instance().acquire(server, export_path);
    if (!handle.nfs) {
        printf("[LibretroVFS] Failed to acquire NFS connection for %s (Hint: %d)\n", path, found_hint);
        fflush(stdout);
        return NULL;
    }

    struct nfsfh *fh = NULL;
    int flags = (mode & RETRO_VFS_FILE_ACCESS_WRITE) ? (O_RDWR | O_CREAT) : O_RDONLY;
    
    {
        std::lock_guard<std::mutex> lock(*handle.mutex);
        if (nfs_open(handle.nfs, filename.c_str(), flags, &fh) != 0) {
            printf("[LibretroVFS] Failed to open file: %s (Error: %s)\n", 
                    filename.c_str(), nfs_get_error(handle.nfs));
            fflush(stdout);
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

    printf("[LibretroVFS] ========================================\n");
    printf("[LibretroVFS] Successfully opened: %s\n", filename.c_str());
    printf("[LibretroVFS]   Size: %llu bytes\n", file->size);
    printf("[LibretroVFS]   Handle: %p\n", (void*)file);
    printf("[LibretroVFS] ========================================\n");
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

static int g_adaptive_timeout_ms = 4; // Start with 4ms

static int64_t retro_vfs_read(struct retro_vfs_file_handle *stream, void *s, uint64_t len) {
    if (!stream || !s) return -1;
    RetroNfsFile* file = (RetroNfsFile*)stream;
    uint8_t* buf = (uint8_t*)s;
    uint64_t start_offset = file->offset;
    
    // Trigger prefetch for current and next blocks
    if (g_prefetch_callback) {
        uint64_t start_block = start_offset / BLOCK_SIZE;
        g_prefetch_callback(start_block);
        g_prefetch_callback(start_block + 1);
        g_prefetch_callback(start_block + 2);
    }

    size_t total_read = 0;
    
    // Step 1: Try reading from cache. 
    // Optimization: Partial Hit Handling. 
    // If we have some blocks in cache but not all, we return what we have IMMEDIATELY 
    // if we've reached a missing block, instead of waiting for EVERY block to be ready.
    while (total_read < len) {
        size_t actual_copied = 0;
        uint64_t current_pos = file->offset + total_read;
        int res = BlockCache::instance().read(current_pos, len - total_read, buf + total_read, &actual_copied);
        
        if (res > 0) {
            total_read += actual_copied;
            if (total_read >= len) break;
            
            // If we didn't read everything, it means the next block is missing.
            // Try to wait for it.
            uint64_t missing_block_id = (file->offset + total_read) / BLOCK_SIZE;
            
            auto start_wait = std::chrono::steady_clock::now();
            bool success = BlockCache::instance().wait_for_block(missing_block_id, g_adaptive_timeout_ms);
            auto end_wait = std::chrono::steady_clock::now();
            auto wait_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end_wait - start_wait).count();

            if (success) {
                // Adjust adaptive timeout down if it was fast
                if (wait_ms < g_adaptive_timeout_ms / 2 && g_adaptive_timeout_ms > 2) {
                    g_adaptive_timeout_ms--;
                }
                // Continue loop to read the newly available block
                continue;
            } else {
                // Timeout. 
                // Adjust adaptive timeout up if we missed it
                if (g_adaptive_timeout_ms < 20) g_adaptive_timeout_ms += 2;
                
                // Partial Hit: If we already read SOME data, return it now.
                // Libretro usually calls again.
                if (total_read > 0) break;
                
                // If we haven't read anything, fall through to sync read
                break;
            }
        } else {
            // First block missing, try wait once
            uint64_t missing_block_id = current_pos / BLOCK_SIZE;
            if (BlockCache::instance().wait_for_block(missing_block_id, g_adaptive_timeout_ms)) {
                continue; // Try read again
            }
            break; // Fallback to sync
        }
    }

    // Step 2: Fallback to sync read for remaining data
    if (total_read < len) {
        uint64_t remaining_len = len - total_read;
        uint64_t current_pos = file->offset + total_read;
        int sync_res = 0;
        {
            std::lock_guard<std::mutex> lock(*file->context_mutex);
            sync_res = nfs_pread(file->nfs, file->fh, buf + total_read, remaining_len, current_pos);
        }

        if (sync_res > 0) {
            // Predictive Backfilling / Predictive Filling
            // If we read a significant amount or exactly aligned blocks, put them in cache.
            uint64_t sync_end = current_pos + sync_res;
            uint64_t first_block = current_pos / BLOCK_SIZE;
            uint64_t last_block = (sync_end - 1) / BLOCK_SIZE;

            for (uint64_t b = first_block; b <= last_block; ++b) {
                uint64_t b_start = b * BLOCK_SIZE;
                uint64_t b_end = b_start + BLOCK_SIZE;
                
                // Only backfill if we have the WHOLE block data in this sync read
                if (current_pos <= b_start && sync_end >= b_end) {
                    size_t buf_offset = b_start - current_pos;
                    BlockCache::instance().put_block(b, buf + total_read + buf_offset, BLOCK_SIZE);
                    // printf("[LibretroVFS] Backfilled block %llu from large sync read\n", b);
                } else if (sync_res < BLOCK_SIZE && g_prefetch_callback) {
                    // If it was a small read, trigger background prefetch for the containing block
                    // so next time it's in cache.
                    g_prefetch_callback(b);
                }
            }
            
            total_read += sync_res;
        }
    }

    if (total_read > 0) {
        file->offset += total_read;
        return (int64_t)total_read;
    }
    
    return -1;
}

static int64_t retro_vfs_write(struct retro_vfs_file_handle *stream, const void *s, uint64_t len) {
    if (!stream) return -1;
    RetroNfsFile* file = (RetroNfsFile*)stream;
    int res = 0;
    {
        std::lock_guard<std::mutex> lock(*file->context_mutex);
        res = nfs_pwrite(file->nfs, file->fh, (void*)s, len, file->offset);
    }
    if (res > 0) {
        // Invalidate cache for the overwritten range
        uint64_t start_block = file->offset / BLOCK_SIZE;
        uint64_t end_block = (file->offset + res - 1) / BLOCK_SIZE;
        for (uint64_t b = start_block; b <= end_block; ++b) {
            BlockCache::instance().invalidate_block(b);
        }
        file->offset += res;
    }
    return res;
}

static int retro_vfs_flush(struct retro_vfs_file_handle *stream) { return 0; }
static int retro_vfs_remove(const char *path) { return -1; }
static int retro_vfs_rename(const char *old_path, const char *new_path) { return -1; }

static int64_t retro_vfs_truncate(struct retro_vfs_file_handle *stream, int64_t length) { return -1; }

static int retro_vfs_stat(const char *path, int32_t *size) {
    if (!path || strncmp(path, "nfs://", 6) != 0) return 0;
    
    // Check Stat Cache first
    struct nfs_stat_64 st_cached;
    if (NfsPool::instance().get_stat_cache(path, &st_cached)) {
        int res = RETRO_VFS_STAT_IS_VALID;
        if (size) *size = (int32_t)st_cached.nfs_size;
        if (S_ISDIR(st_cached.nfs_mode)) res |= RETRO_VFS_STAT_IS_DIRECTORY;
        return res;
    }

    // Fallback to network stat
    std::string server, export_path, filename;
    bool found_hint = false;

    {
        std::lock_guard<std::mutex> lock(g_hint_mutex);
        if (g_path_hints.count(path)) {
            const auto& hint = g_path_hints[path];
            server = hint.server;
            export_path = hint.export_path;
            filename = hint.relative_path;
            found_hint = true;
            printf("[LibretroVFS] Hint FOUND for %s -> Server: %s, Export: %s, File: %s\n", 
                    path, server.c_str(), export_path.c_str(), filename.c_str());
            fflush(stdout);
        }
    }

    if (!found_hint) {
        struct nfs_context *nfs_tmp = nfs_init_context();
        if (!nfs_tmp) return 0;
        struct nfs_url *url = nfs_parse_url_dir(nfs_tmp, path);
        if (!url) {
            nfs_destroy_context(nfs_tmp);
            return 0;
        }
        server = url->server;
        export_path = url->path;
        filename = url->file ? url->file : "";
        nfs_destroy_url(url);
        nfs_destroy_context(nfs_tmp);
    }

    NfsPool::ConnectionHandle handle = NfsPool::instance().acquire(server, export_path);
    if (!handle.nfs) return 0;

    struct nfs_stat_64 st;
    int res = 0;
    {
        std::lock_guard<std::mutex> lock(*handle.mutex);
        if (nfs_stat64(handle.nfs, filename.c_str(), &st) == 0) {
            res |= RETRO_VFS_STAT_IS_VALID;
            if (size) *size = (int32_t)st.nfs_size;
            if (S_ISDIR(st.nfs_mode)) res |= RETRO_VFS_STAT_IS_DIRECTORY;
            
            // Put in cache
            NfsPool::instance().put_stat_cache(path, st);
        }
    }
    NfsPool::instance().release(handle.nfs);
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

    EXPORT void bridge_fill_vfs_info(void* data, struct retro_vfs_interface* iface) {
        printf("[LibretroVFS] bridge_fill_vfs_info CALLED\n");
        printf("[LibretroVFS]   data: %p, iface: %p\n", data, (void*)iface);
        fflush(stdout);
        
        if (!data || !iface) {
            printf("[LibretroVFS] ERROR: data or iface is NULL!\n");
            fflush(stdout);
            return;
        }
        
        uint32_t* u = (uint32_t*)data;
        printf("[LibretroVFS] Raw data bytes: [0]=%u, [1]=%u, [2]=%u, [3]=%u\n", u[0], u[1], u[2], u[3]);
        fflush(stdout);
        
        // Surgical fix: Offset 8 is the standard for 64-bit platforms
        if (u[0] >= 1 && u[0] <= 10) {
            void** target = (void**)((char*)data + 8);
            printf("[LibretroVFS] Before injection: *target = %p\n", *target);
            *target = iface;
            printf("[LibretroVFS] Surgically injected VFS at offset 8 (Version %u)\n", u[0]);
            printf("[LibretroVFS] After injection: *target = %p\n", *target);
        } else {
            // Fallback for non-standard layouts or if version detection fails
            struct retro_vfs_interface_info* info = (struct retro_vfs_interface_info*)data;
            info->iface = iface;
            printf("[LibretroVFS] Standard version check failed, using struct-based write (data=%p, version=%u)\n", data, u[0]);
        }
        fflush(stdout);
    }
}
