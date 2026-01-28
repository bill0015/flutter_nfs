#ifndef LIBRETRO_DEFINES_H
#define LIBRETRO_DEFINES_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations
struct retro_vfs_file_handle;
struct retro_vfs_dir_handle;

/* VFS API version */
#define RETRO_VFS_INTERFACE_VERSION 3

/* File open modes */
#define RETRO_VFS_FILE_ACCESS_READ            (1 << 0)
#define RETRO_VFS_FILE_ACCESS_WRITE           (1 << 1)
#define RETRO_VFS_FILE_ACCESS_READ_WRITE      (RETRO_VFS_FILE_ACCESS_READ | RETRO_VFS_FILE_ACCESS_WRITE)
#define RETRO_VFS_FILE_ACCESS_UPDATE_EXISTING (1 << 2)

/* Seek positions */
#define RETRO_VFS_SEEK_POSITION_START    0
#define RETRO_VFS_SEEK_POSITION_CURRENT  1
#define RETRO_VFS_SEEK_POSITION_END      2

/* Stat */
#define RETRO_VFS_STAT_IS_DIRECTORY (1 << 0)
#define RETRO_VFS_STAT_IS_CHARACTER_SPECIAL (1 << 1)

struct retro_vfs_interface {
   /* V1 */
   const char *(*get_path)(struct retro_vfs_file_handle *stream);
   struct retro_vfs_file_handle *(*open)(const char *path, unsigned mode, unsigned hints);
   int (*close)(struct retro_vfs_file_handle *stream);
   int64_t (*size)(struct retro_vfs_file_handle *stream);
   int64_t (*tell)(struct retro_vfs_file_handle *stream);
   int64_t (*seek)(struct retro_vfs_file_handle *stream, int64_t offset, int seek_position);
   int64_t (*read)(struct retro_vfs_file_handle *stream, void *s, uint64_t len);
   int64_t (*write)(struct retro_vfs_file_handle *stream, const void *s, uint64_t len);
   int (*flush)(struct retro_vfs_file_handle *stream);
   int (*remove)(const char *path);
   int (*rename)(const char *old_path, const char *new_path);
   /* V2 */
   int64_t (*truncate)(struct retro_vfs_file_handle *stream, int64_t length);
   /* V3 */
   int (*stat)(const char *path, int32_t *size);
   int (*mkdir)(const char *dir);
   struct retro_vfs_dir_handle *(*opendir)(const char *dir, bool include_hidden);
   bool (*readdir)(struct retro_vfs_dir_handle *dhandle);
   const char *(*dirent_get_name)(struct retro_vfs_dir_handle *dhandle);
   bool (*dirent_is_dir)(struct retro_vfs_dir_handle *dhandle);
   int (*closedir)(struct retro_vfs_dir_handle *dhandle);
};

struct retro_vfs_interface_info {
   uint32_t required_interface_version;
   struct retro_vfs_interface *iface;
};

#ifdef __cplusplus
}
#endif

#endif // LIBRETRO_DEFINES_H
