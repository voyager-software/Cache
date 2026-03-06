import Foundation

/// Manage storage. Use memory storage if specified.
public final class Storage: Sendable {
    // MARK: Lifecycle

    /// Initialize disk-based storage, optionally backed by a memory cache.
    ///
    /// - Parameters:
    ///   - diskConfig: Configuration for disk storage
    ///   - memoryConfig: Optional. Pass config to add an in-memory layer
    /// - Throws: Throw StorageError if any.
    public init(diskConfig: DiskConfig, memoryConfig: MemoryConfig? = nil) throws {
        let storage: StorageAware
        let disk = try DiskStorage(config: diskConfig)

        if let memoryConfig {
            let memory = MemoryStorage(config: memoryConfig)
            storage = HybridStorage(memoryStorage: memory, diskStorage: disk)
        }
        else {
            storage = disk
        }

        self.internalStorage = TypeWrapperStorage(storage: storage)
    }

    /// Initialize memory-only storage.
    ///
    /// - Parameter memoryConfig: Configuration for memory storage
    public init(memoryConfig: MemoryConfig) {
        let memory = MemoryStorage(config: memoryConfig)
        self.internalStorage = TypeWrapperStorage(storage: memory)
    }

    // MARK: Private

    /// Internal storage implementation
    private let internalStorage: StorageAware
}

extension Storage: StorageAware {
    public func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
        try self.internalStorage.entry(ofType: type, forKey: key)
    }

    public func removeObject(forKey key: String) throws {
        try self.internalStorage.removeObject(forKey: key)
    }

    public func setObject(_ object: some Codable & Sendable, forKey key: String, expiry: Expiry? = nil) throws {
        try self.internalStorage.setObject(object, forKey: key, expiry: expiry)
    }

    public func removeAll() throws {
        try self.internalStorage.removeAll()
    }

    public func removeExpiredObjects() throws {
        try self.internalStorage.removeExpiredObjects()
    }
}
