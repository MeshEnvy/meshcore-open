import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/mal/kv/sqflite_kv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Setup sqflite ffi for tests
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('KV Store Scoping Tests', () {
    late SqfliteKvStore kvStore;

    setUp(() async {
      kvStore = SqfliteKvStore.instance;
      kvStore.overrideDatabasePath(inMemoryDatabasePath);
      await kvStore.init();
    });

    test('Values are isolated between scopes', () async {
      await kvStore.set('my_key', 'global_val'); // default scope 'global'
      await kvStore.set('my_key', 'env_val', scope: 'env');
      await kvStore.set('my_key', 'vfs_val', scope: 'vfs');

      expect(await kvStore.get('my_key'), equals('global_val'));
      expect(
        await kvStore.get('my_key', scope: 'global'),
        equals('global_val'),
      );
      expect(await kvStore.get('my_key', scope: 'env'), equals('env_val'));
      expect(await kvStore.get('my_key', scope: 'vfs'), equals('vfs_val'));
    });

    test('getKeys only returns keys for the specified scope', () async {
      await kvStore.set('key1', 'v1', scope: 's1');
      await kvStore.set('key2', 'v2', scope: 's1');
      await kvStore.set('key3', 'v3', scope: 's2');

      final s1Keys = await kvStore.getKeys(scope: 's1');
      expect(s1Keys, containsAll(['key1', 'key2']));
      expect(s1Keys, isNot(contains('key3')));

      final s2Keys = await kvStore.getKeys(scope: 's2');
      expect(s2Keys, contains('key3'));
      expect(s2Keys, isNot(contains('key1')));
      expect(s2Keys, isNot(contains('key2')));
    });

    test('delete only affects the specified scope', () async {
      await kvStore.set('shared_key', 'v1', scope: 's1');
      await kvStore.set('shared_key', 'v2', scope: 's2');

      await kvStore.delete('shared_key', scope: 's1');

      expect(await kvStore.get('shared_key', scope: 's1'), isNull);
      expect(await kvStore.get('shared_key', scope: 's2'), equals('v2'));
    });
  });
}
