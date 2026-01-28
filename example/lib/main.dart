import 'package:flutter/material.dart';
import 'package:flutter_nfs/flutter_nfs.dart';

void main() {
  runApp(const NfsExampleApp());
}

class NfsExampleApp extends StatelessWidget {
  const NfsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFS Example',
      theme: ThemeData.dark(),
      home: const NfsExamplePage(),
    );
  }
}

class NfsExamplePage extends StatefulWidget {
  const NfsExamplePage({super.key});

  @override
  State<NfsExamplePage> createState() => _NfsExamplePageState();
}

class _NfsExamplePageState extends State<NfsExamplePage> {
  final _serverController = TextEditingController(text: '192.168.1.100');
  final _pathController = TextEditingController(text: '/roms');
  final _portController = TextEditingController(text: '2049');

  NfsClient? _client;
  List<NfsEntry> _entries = [];
  String _status = 'Not connected';
  bool _isLoading = false;

  @override
  void dispose() {
    _client?.dispose();
    _serverController.dispose();
    _pathController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _isLoading = true;
      _status = 'Connecting...';
    });

    try {
      _client?.dispose();

      final url = NfsUrl.build(
        host: _serverController.text,
        path: _pathController.text,
        nfsPort: int.tryParse(_portController.text),
      );

      _client = NfsClient();
      await _client!.mount(url);

      final entries = await _client!.listDir('/');

      setState(() {
        _entries = entries;
        _status = 'Connected! Found ${entries.length} items';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _entries = [];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _readFile(String name) async {
    if (_client == null) return;

    setState(() {
      _isLoading = true;
      _status = 'Reading $name...';
    });

    try {
      final size = await _client!.stat('/$name');
      final bytes = await _client!.read('/$name', 0, size);

      if (mounted) {
        setState(() {
          _status = 'Read ${bytes.length} bytes from $name ($size total)';
        });
      }
    } catch (e) {
      setState(() => _status = 'Error reading $name: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NFS Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(labelText: 'Server'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(labelText: 'Export Path'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _connect,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
            const SizedBox(height: 16),
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return ListTile(
                    leading: Icon(
                      entry.isDirectory
                          ? Icons.folder
                          : Icons.insert_drive_file,
                    ),
                    title: Text(entry.name),
                    subtitle: Text('${entry.size} bytes'),
                    onTap:
                        entry.isDirectory ? null : () => _readFile(entry.name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
