/// The generic Key-Value Store used by the Mesh Abstraction Layer (MAL)
/// to hold high-performance structured metrics, scoped environment variables,
/// and fast native fallback storage for the VFS.
abstract class MeshKvStore {
  /// Initializes the KV store. Implementations should handle DB creation,
  /// schema setup, and any platform-specific ready-wait states.
  Future<void> init();

  /// Retrieves a string value for a given key within a specific scope.
  Future<String?> get(String key, String scope);

  /// Sets a string value for a given key within a specific scope.
  Future<void> set(String key, String value, String scope);

  /// Deletes a specific key within a specific scope.
  Future<void> delete(String key, String scope);

  /// Returns all keys that match a specific scope. Useful for iterating
  /// over all environment variables or virtual files for a node.
  Future<List<String>> getKeys(String scope);
}
