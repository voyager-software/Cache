import Foundation
import os

/// Use both memory and disk storage. Try on memory first.
final class HybridStorage: Sendable {
    // MARK: Lifecycle

    init(memoryStorage: MemoryStorage, diskStorage: DiskStorage) {
        self.memoryStorage = memoryStorage
        self.diskStorage = diskStorage
    }

    // MARK: Private

    private let memoryStorage: MemoryStorage
    private let diskStorage: DiskStorage
    /// Lock for atomic cross-storage operations
    private let lock = OSAllocatedUnfairLock()
}

extension HybridStorage: StorageAware {
    func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
        try self.lock.withLockUnchecked {
            do {
                return try self.memoryStorage.entry(ofType: type, forKey: key)
            }
            catch {
                let entry = try diskStorage.entry(ofType: type, forKey: key)
                // set back to memoryStorage
                self.memoryStorage.setObject(entry.object, forKey: key, expiry: entry.expiry)
                return entry
            }
        }
    }

    func removeObject(forKey key: String) throws {
        try self.lock.withLockUnchecked {
            self.memoryStorage.removeObject(forKey: key)
            try self.diskStorage.removeObject(forKey: key)
        }
    }

    func setObject(_ object: some Codable & Sendable, forKey key: String, expiry: Expiry? = nil) throws {
        try self.lock.withLockUnchecked {
            self.memoryStorage.setObject(object, forKey: key, expiry: expiry)
            try self.diskStorage.setObject(object, forKey: key, expiry: expiry)
        }
    }

    func removeAll() throws {
        try self.lock.withLockUnchecked {
            self.memoryStorage.removeAll()
            try self.diskStorage.removeAll()
        }
    }

    func removeExpiredObjects() throws {
        try self.lock.withLockUnchecked {
            self.memoryStorage.removeExpiredObjects()
            try self.diskStorage.removeExpiredObjects()
        }
    }
}
