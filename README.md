# flutter_nfs

A high-performance, cross-platform **user-space** NFS client for Flutter, powered by `libnfs`.

Unlike traditional NFS mounts that require kernel support (and often root access on mobile), `flutter_nfs` runs entirely in user-space. This makes it ideal for applications that need to access network storage without requiring special device permissions or OS-level configuration, such as game emulators, media players, or file managers.

## 🚀 Key Features

*   **User-Space Implementation**: Runs completely within the application process. No root access or kernel modules required on Android/iOS.
*   **Cross-Platform**: Supports **Android**, **iOS**, **macOS**, **Windows**, and **Linux**.
*   **High Performance**:
    *   **Zero-Copy Architecture**: Data is read directly from the network socket into Dart `Uint8List` buffers, minimizing memory overhead.
    *   **Block Cache**: Built-in 128KB ring buffer cache for optimized sequential read performance (ideal for streaming media or emulators).
    *   **Connection Pooling**: Efficiently manages `nfs_context` connections.
*   **Asynchronous & Thread-Safe**: All operations run in a dedicated background Isolate, ensuring your UI remains 60fps smooth.
*   **Comprehensive API**: Support for NFSv3/v4 including file creation, writing, directory listing, and permissions management.

## 📦 Installation

Add `flutter_nfs` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_nfs: ^0.1.0
```

## 🛠️ Usage

### 1. Initialization

Initialize the client to spawn the background worker isolate.

```dart
import 'package:flutter_nfs/flutter_nfs.dart';

final client = NfsClient();
await client.init();
```

### 2. Connect to NFS Server

Mount an NFS export via URL. Standard `nfs://` scheme is supported.

```dart
// Format: nfs://<server>/<export_path>
await client.mount('nfs://192.168.1.100/volume1/shared');
```

**Note**: By default, `libnfs` may try to use privileged ports. For non-root usage (typical on mobile), ensure your NFS server allows insecure ports (often the `insecure` export option).

### 3. File Operations

#### List Directory
```dart
final entries = await client.listDir('/');
for (var entry in entries) {
  print('${entry.name} - ${entry.isDirectory ? "Dir" : "File"}');
}
```

#### Read File
```dart
// Read 1024 bytes from offset 0
final bytes = await client.read('/data.txt', 0, 1024);
```

#### Write File
```dart
final content = utf8.encode('Hello NFS');
// Write data to offset 0
await client.write('/new_file.txt', content, 0);
```

#### Manage Files
```dart
// Create Directory
await client.mkdir('/new_folder');

// Create Empty File
await client.createFile('/new_folder/empty.txt');

// Rename/Move
await client.rename('/new_folder/empty.txt', '/new_folder/renamed.txt');

// Delete
await client.delete('/new_folder/renamed.txt');
```

## 🏗️ Architecture

`flutter_nfs` is built as a layered architecture to provide safety and performance:

1.  **Dart API (`NfsClient`)**: The high-level, asynchronous API running in the main Isolate.
2.  **Worker Isolate**: A dedicated background thread that handles all FFI calls to prevent UI blocking.
3.  **FFI Bridge**: Dart `ffi` bindings to the native C functions.
4.  **Native Core (`libnfs`)**:
    *   **Shared Library**: The `libnfs` C library handles the NFS protocol (RPC, XDR).
    *   **NfsPool**: A connection pool manager to handle multiple concurrent contexts if needed.
    *   **BlockCache**: A C++ ring buffer optimization that reduces small I/O calls by pre-fetching data.

## 🧩 Supported Operations

| Operation | Description |
| :--- | :--- |
| `mount` | Connect to an NFS export. |
| `listDir` | List directory contents with metadata. |
| `read` | Read byte ranges from a file. |
| `write` | Write byte ranges into a file. |
| `createFile` | Create a new empty file. |
| `mkdir` | Create a new directory. |
| `delete` | Delete a file (`unlink`). |
| `rmdir` | Delete a directory. |
| `rename` | Rename or move a file/directory. |
| `truncate` | Resize a file. |
| `chmod` | Change file permissions. |
| `chown` | Change file ownership. |
| `stat` | Get file size and attributes. |

## 📝 License

This project is licensed under the MIT License. `libnfs` is licensed under LGPL/GPL.
