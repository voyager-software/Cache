import Foundation

/// Manage storage. Use memory storage if specified.
public final class Storage: Sendable {
    // MARK: Lifecycle

    /// Initialize disk-based storage, optionally backed by a memory cache.
    ///
    /// - Parameters:
    ///   - diskConfig: Configuration for disk storage
    ///   - memoryConfig: Optional. Pass config to add an in-memory layer
    /// - Throws: `CocoaError(.fileWriteInvalidFileName)` if the config's name isn't a single folder name,
    ///   or the file system's error if the folder can't be created.
    public init(diskConfig: DiskConfig, memoryConfig: MemoryConfig? = nil) throws {
        let disk = try DiskStorage(config: diskConfig)

        if let memoryConfig {
            let memory = MemoryStorage(config: memoryConfig)
            self.internalStorage = HybridStorage(memoryStorage: memory, diskStorage: disk)
        }
        else {
            self.internalStorage = disk
        }
    }

    /// Initialize memory-only storage.
    ///
    /// - Parameter memoryConfig: Configuration for memory storage
    public init(memoryConfig: MemoryConfig) {
        self.internalStorage = MemoryStorage(config: memoryConfig)
    }

    // MARK: Private

    /// Internal storage implementation
    private let internalStorage: StorageAware
}

extension Storage: StorageAware {
    /**
     Tries to retrieve the object from the storage. Use the type the object was written as: with
     any other type, the kinds of storage can give different results, including the file's raw
     bytes when asking for `Data`.
     - Parameter key: Unique key to identify the object in the cache
     - Returns: Cached object
     - Throws: `StorageError.notFound` if there's no object for the key, or it has expired
     */
    public func object<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> T {
        try self.internalStorage.object(ofType: type, forKey: key)
    }

    /**
     Tries to retrieve the object together with its expiry date.
     - Parameter key: Unique key to identify the object in the cache
     - Returns: Object wrapper with its expiry date
     - Throws: `StorageError.notFound` if there's no object for the key, or it has expired
     */
    public func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
        try self.internalStorage.entry(ofType: type, forKey: key)
    }

    /**
     Check if a non-expired object exists for the given key.
     Does not read the object, so a read can still fail after this returns `true`, for example
     for a file with `.complete` protection while the device is locked.
     - Parameter key: Unique key to identify the object.
     */
    public func existsObject(forKey key: String) throws -> Bool {
        try self.internalStorage.existsObject(forKey: key)
    }

    /**
     Removes the object by the given key. Does nothing if there's no object for the key.
     - Parameter key: Unique key to identify the object.
     */
    public func removeObject(forKey key: String) throws {
        try self.internalStorage.removeObject(forKey: key)
    }

    /**
     Saves passed object.
     - Parameter object: Object that needs to be cached.
     - Parameter key: Unique key to identify the object in the cache.
     - Parameter expiry: Overwrite expiry for this object only.
     */
    public func setObject(_ object: some Codable & Sendable, forKey key: String, expiry: Expiry? = nil) throws {
        try self.internalStorage.setObject(object, forKey: key, expiry: expiry)
    }

    /**
     Removes all objects from the cache storage. On disk, it deletes the storage's own files,
     including ones from an older version of this package, and leaves anything else in the folder.
     A file that can't be removed doesn't stop the others. The first failure is thrown at the end.
     */
    public func removeAll() throws {
        try self.internalStorage.removeAll()
    }

    /**
     Clears all expired objects, and files left behind by an older version of this package, whatever
     their age. Only files named like the storage's objects, directly in its folder, are ever deleted.
     A file that can't be removed doesn't stop the others. The first failure is thrown at the end.
     */
    public func removeExpiredObjects() throws {
        try self.internalStorage.removeExpiredObjects()
    }

    /**
     How much disk space the storage takes up, in bytes. 0 for memory-only storage.
     */
    public func diskSize() throws -> UInt64 {
        try self.internalStorage.diskSize()
    }
}
