## 0.2.0
*   Renamed package to `flutter_nfs`.
*   Added comprehensive write support (`write`, `createFile`, `truncate`, `fsync`).
*   Added file management operations (`delete`, `mkdir`, `rmdir`, `rename`, `chmod`, `chown`).
*   Added high-level `NfsClient` API for file operations.
*   Updated documentation and examples.

## 0.1.0

*   Initial release.
*   Support for NFSv3/NFSv4.
*   Zero-copy reads via Dart FFI.
*   Portmapper bypass optimization.
