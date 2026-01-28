import 'dart:convert';
import 'package:flutter_nfs/flutter_nfs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Use the same URL as the read test
  const testUrl = 'nfs://10.20.1.39/Users/bill/Downloads/sharenfs';
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final testDir = '/write_test_$timestamp';
  final testFile = '$testDir/hello.txt';
  final renamedFile = '$testDir/renamed.txt';
  final testContent = utf8.encode('Hello NFS World from Flutter!');

  group('NfsClient Write & Management Integration Test', () {
    late NfsClient client;

    setUp(() async {
      client = NfsClient();
      await client.init();
      await client.mount(testUrl);
    });

    tearDown(() {
      client.dispose();
    });

    testWidgets('Full Write Cycle', (WidgetTester tester) async {
      print('[Test] Starting Write Cycle Test...');

      // 1. Mkdir
      print('[Test] Creating directory: $testDir');
      await client.mkdir(testDir);

      // Verify dir exists
      final entries = await client.listDir('/');
      expect(entries.any((e) => e.name == testDir.substring(1)), isTrue);

      // 2. Create File
      print('[Test] Creating file: $testFile');
      await client.createFile(testFile);

      // 3. Write Content
      print('[Test] Writing content...');
      await client.write(testFile, testContent, 0);

      // 4. Read Verification
      print('[Test] Reading back content...');
      final readBytes = await client.read(testFile, 0, testContent.length);
      expect(readBytes, equals(testContent));
      print('[Test] Content verified!');

      // 5. Rename
      print('[Test] Renaming $testFile to $renamedFile');
      await client.rename(testFile, renamedFile);

      expect(await client.exists(testFile), isFalse);
      expect(await client.exists(renamedFile), isTrue);

      // 6. Truncate
      print('[Test] Truncating file to 5 bytes...');
      await client.truncate(renamedFile, 5);
      final truncatedBytes =
          await client.read(renamedFile, 0, 10); // Try read more
      expect(truncatedBytes.length, equals(5));
      expect(utf8.decode(truncatedBytes), equals('Hello'));

      // 7. Delete File
      print('[Test] Deleting $renamedFile');
      await client.delete(renamedFile);
      expect(await client.exists(renamedFile), isFalse);

      // 8. Rmdir
      print('[Test] Removing directory $testDir');
      await client.rmdir(testDir);

      final entriesFinal = await client.listDir('/');
      expect(entriesFinal.any((e) => e.name == testDir.substring(1)), isFalse);

      print('[Test] Write Cycle Test Passed!');
    });
  });
}
