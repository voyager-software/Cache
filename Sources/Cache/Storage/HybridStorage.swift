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
    /// Keeps memory and disk in step when changing them, and counts those changes. The count lets
    /// a read notice that the object it just decoded may be out of date.
    private let lock = OSAllocatedUnfairLock(initialState: 0)
}

extension HybridStorage: StorageAware {
    func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
        // Without the lock, so that a hit doesn't wait for another object's disk access
        if let entry = try? self.memoryStorage.entry(ofType: type, forKey: key) {
            return entry
        }

        // Decoding happens without the lock too, so the object may be removed or replaced meanwhile.
        // Memory is only filled if nothing changed, or this would bring back the old object.
        let changeCount = self.lock.withLockUnchecked { $0 }
        let entry = try diskStorage.entry(ofType: type, forKey: key)
        self.lock.withLockUnchecked { currentCount in
            if currentCount == changeCount {
                self.memoryStorage.setObject(entry.object, forKey: key, expiry: entry.expiry)
            }
        }
        return entry
    }

    func existsObject(forKey key: String) throws -> Bool {
        if self.memoryStorage.existsObject(forKey: key) {
            return true
        }
        return try self.diskStorage.existsObject(forKey: key)
    }

    func removeObject(forKey key: String) throws {
        try self.lock.withLockUnchecked { changeCount in
            changeCount += 1
            self.memoryStorage.removeObject(forKey: key)
            try self.diskStorage.removeObject(forKey: key)
        }
    }

    func setObject(_ object: some Codable & Sendable, forKey key: String, expiry: Expiry? = nil) throws {
        let data = try diskStorage.encode(object, forKey: key)

        try self.lock.withLockUnchecked { changeCount in
            changeCount += 1
            // Disk first, because it's the one that can fail. Memory then never holds what wasn't saved.
            // An object has one expiry: the disk works it out once it has its own lock, and the copy
            // in memory gets the same date, so it can't outlive the file.
            let date = try self.diskStorage.write(data, forKey: key, expiry: expiry)
            self.memoryStorage.setObject(object, forKey: key, expiry: .date(date))
        }
    }

    func removeAll() throws {
        try self.lock.withLockUnchecked { changeCount in
            changeCount += 1
            self.memoryStorage.removeAll()
            try self.diskStorage.removeAll()
        }
    }

    func removeExpiredObjects() throws {
        try self.lock.withLockUnchecked { _ in
            self.memoryStorage.removeExpiredObjects()
            try self.diskStorage.removeExpiredObjects()
        }
    }

    func diskSize() throws -> UInt64 {
        try self.diskStorage.diskSize()
    }
}
