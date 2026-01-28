import 'package:flutter_nfs/flutter_nfs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testUrl = 'nfs://10.20.1.39/Users/bill/Downloads/sharenfs';

  // "Contra (USA).nes" is a regular file we saw in the listing (131088 bytes)
  const testFile = '/Contra (USA).nes';

  // A file that definitely doesn't exist
  const nonExistentFile = '/definitely_does_not_exist.txt';

  group('NfsClient Full Integration Test', () {
    late NfsClient client;

    setUp(() async {
      client = NfsClient();
      await client.init();
    });

    tearDown(() {
      client.dispose();
    });

    testWidgets('Initialization and Mount', (WidgetTester tester) async {
      print('[Test] Mounting $testUrl...');
      await client.mount(testUrl);
      print('[Test] Mount successful');
    });

    testWidgets('List Directory (Root)', (WidgetTester tester) async {
      await client.mount(testUrl);
      print('[Test] Listing directory / ...');
      final entries = await client.listDir('/');

      expect(entries, isNotEmpty);
      print('[Test] Found ${entries.length} entries');

      for (var entry in entries) {
        print(
            '[Test Entry] ${entry.name} (Size: ${entry.size}, Directory: ${entry.isDirectory})');
      }

      // Verify known entries exist
      expect(entries.any((e) => e.name == 'fbneo'), isTrue,
          reason: 'fbneo file should exist');
      expect(entries.any((e) => e.name == '.DS_Store'), isTrue,
          reason: '.DS_Store should exist');
    });

    testWidgets('File Existence Check', (WidgetTester tester) async {
      await client.mount(testUrl);

      print('[Test] Checking existence of $testFile');
      final exists = await client.exists(testFile);
      expect(exists, isTrue);

      print('[Test] Checking existence of $nonExistentFile');
      final notExists = await client.exists(nonExistentFile);
      expect(notExists, isFalse);
    });

    testWidgets('File Statistics (Stat)', (WidgetTester tester) async {
      await client.mount(testUrl);

      print('[Test] Stat $testFile');
      final size = await client.stat(testFile);
      print('[Test] Size of $testFile: $size bytes');

      // Based on previous run, Contra (USA).nes was 131088 bytes.
      expect(size, greaterThan(0));
      expect(size, equals(131088));
    });

    testWidgets('Read File Content', (WidgetTester tester) async {
      await client.mount(testUrl);

      print('[Test] Reading first 16 bytes of $testFile');
      final bytes = await client.read(testFile, 0, 16);

      expect(bytes.length, equals(16));
      print('[Test] Bytes read: $bytes');

      // Read end of file part
      print('[Test] Reading rest of file...');
      final fullBytes = await client.read(testFile, 0, 131088);
      expect(fullBytes.length, equals(131088));
    });

    testWidgets('Error Handling: Invalid Mount', (WidgetTester tester) async {
      const invalidUrl =
          'nfs://10.20.1.31/Users/bill/Downloads/invalid_share_path';
      print('[Test] Attempting to mount invalid URL: $invalidUrl');

      try {
        await client.mount(invalidUrl);
        fail('Should have thrown an error');
      } catch (e) {
        print('[Test] Caught expected error: $e');
        expect(e.toString(), contains('Mount failed'));
      }
    });

    testWidgets('Error Handling: Read Non-Existent File',
        (WidgetTester tester) async {
      await client.mount(testUrl);
      print('[Test] Attempting to read $nonExistentFile');

      try {
        await client.read(nonExistentFile, 0, 10);
        fail('Should have thrown an error');
      } catch (e) {
        print('[Test] Caught expected error: $e');
        // The error message format depends on libnfs error string,
        // usually includes "No such file or directory" or generic failure
        expect(e.toString(), isNotEmpty);
      }
    });
  });
}
