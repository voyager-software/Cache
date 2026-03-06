import Foundation

/// Manage storage. Use memory storage if specified.
public final class Storage: Sendable {
  /// Internal storage implementation
  private let internalStorage: StorageAware

  /// Initialize storage with configuration options.
  ///
  /// - Parameters:
  ///   - diskConfig: Configuration for disk storage
  ///   - memoryConfig: Optional. Pass config if you want memory cache
  /// - Throws: Throw StorageError if any.
  public init(diskConfig: DiskConfig, memoryConfig: MemoryConfig? = nil) throws {
    // Disk or Hybrid
    let storage: StorageAware
    let disk = try DiskStorage(config: diskConfig)

    if let memoryConfig = memoryConfig {
      let memory = MemoryStorage(config: memoryConfig)
      storage = HybridStorage(memoryStorage: memory, diskStorage: disk)
    } else {
      storage = disk
    }

    self.internalStorage = TypeWrapperStorage(storage: storage)
  }
}

extension Storage: StorageAware {
  public func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
    return try internalStorage.entry(ofType: type, forKey: key)
  }

  public func removeObject(forKey key: String) throws {
    try internalStorage.removeObject(forKey: key)
  }

  public func setObject<T: Codable & Sendable>(_ object: T, forKey key: String,
                                    expiry: Expiry? = nil) throws {
    try internalStorage.setObject(object, forKey: key, expiry: expiry)
  }

  public func removeAll() throws {
    try internalStorage.removeAll()
  }

  public func removeExpiredObjects() throws {
    try internalStorage.removeExpiredObjects()
  }
}
