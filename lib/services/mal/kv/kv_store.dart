/// The generic Key-Value Store used by the Mesh Abstraction Layer (MAL)
/// to hold high-performance structured metrics, scoped environment variables,
/// and fast native fallback storage for the VFS.
abstract class MeshKvStore {
  /// Initializes the KV store. Implementations should handle DB creation,
  /// schema setup, and any platform-specific ready-wait states.
  Future<void> init();

  /// Retrieves a string value for a given key.
  Future<String?> get(String key, {String? scope});

  /// Sets a string value for a given key.
  Future<void> set(String key, String value, {String? scope});

  /// Deletes a specific key.
  Future<void> delete(String key, {String? scope});

  /// Returns all keys. Useful for iterating
  /// over all environment variables or virtual files.
  Future<List<String>> getKeys({String? scope});
}
