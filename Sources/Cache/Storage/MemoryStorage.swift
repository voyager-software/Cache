import Foundation
import os

/// Save objects to memory based on NSCache
final class MemoryStorage: Sendable {
    // MARK: Lifecycle

    init(config: MemoryConfig) {
        self.config = config
        self.cache.countLimit = Int(config.countLimit)
    }

    // MARK: Private

    /// Memory cache instance (NSCache is thread-safe)
    private nonisolated(unsafe) let cache = NSCache<NSString, MemoryCapsule>()
    /// Memory cache keys, protected by a lock
    private let lockedKeys = OSAllocatedUnfairLock(initialState: Set<String>())
    /// Configuration
    private let config: MemoryConfig
}

extension MemoryStorage: StorageAware {
    func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
        guard let capsule = cache.object(forKey: key as NSString) else {
            throw StorageError.notFound(key: key)
        }

        guard let object = capsule.object as? T else {
            throw StorageError.typeNotMatch(key: key)
        }

        return Entry(object: object, expiry: capsule.expiry)
    }

    func existsObject(forKey key: String) -> Bool {
        guard let capsule = cache.object(forKey: key as NSString) else {
            return false
        }
        return !capsule.expiry.isExpired
    }

    func removeObject(forKey key: String) {
        self.cache.removeObject(forKey: key as NSString)
        self.lockedKeys.withLock { _ = $0.remove(key) }
    }

    func setObject(_ object: some Codable & Sendable, forKey key: String, expiry: Expiry? = nil) {
        let capsule = MemoryCapsule(value: object, expiry: .date(expiry?.date ?? self.config.expiry.date))
        self.cache.setObject(capsule, forKey: key as NSString)
        self.lockedKeys.withLock { _ = $0.insert(key) }
    }

    func removeAll() {
        self.cache.removeAllObjects()
        self.lockedKeys.withLock { $0.removeAll() }
    }

    func removeExpiredObjects() {
        let allKeys = self.lockedKeys.withLock { $0 }
        for key in allKeys {
            removeObjectIfExpired(forKey: key)
        }
    }
}

extension MemoryStorage {
    /**
     Removes the object from the cache if it's expired.
     - Parameter key: Unique key to identify the object in the cache
     */
    private func removeObjectIfExpired(forKey key: String) {
        if let capsule = cache.object(forKey: key as NSString), capsule.expiry.isExpired {
            self.removeObject(forKey: key)
        }
    }
}

/// Helper class to hold cached instance and expiry date.
/// Used in memory storage to work with NSCache.
/// Immutable and only accessed through NSCache (which is thread-safe).
private final class MemoryCapsule: NSObject, @unchecked Sendable {
    // MARK: Lifecycle

    init(value: any Sendable, expiry: Expiry) {
        self.object = value
        self.expiry = expiry
    }

    // MARK: Internal

    /// Object to be cached
    let object: any Sendable
    /// Expiration date
    let expiry: Expiry
}
