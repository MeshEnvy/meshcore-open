library indexed_db_kv;

import 'kv_store.dart';
import 'indexed_db_kv_stub.dart'
    if (dart.library.js_interop) 'indexed_db_kv_web.dart';

export 'indexed_db_kv_stub.dart'
    if (dart.library.js_interop) 'indexed_db_kv_web.dart';

/// A factory/provider for the IndexedDbKvStore.
class IndexedDbKvStoreProvider {
  /// Gets the singleton instance for the current platform.
  static MeshKvStore get instance => getIndexedDbKvStore();
}
