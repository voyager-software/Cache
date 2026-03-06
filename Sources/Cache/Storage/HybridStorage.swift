import Foundation
import os

/// Use both memory and disk storage. Try on memory first.
final class HybridStorage: Sendable {
  private let memoryStorage: MemoryStorage
  private let diskStorage: DiskStorage
  /// Lock for atomic cross-storage operations
  private let lock = OSAllocatedUnfairLock()

  init(memoryStorage: MemoryStorage, diskStorage: DiskStorage) {
    self.memoryStorage = memoryStorage
    self.diskStorage = diskStorage
  }
}

extension HybridStorage: StorageAware {
  func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
    try lock.withLockUnchecked {
      do {
        return try memoryStorage.entry(ofType: type, forKey: key)
      } catch {
        let entry = try diskStorage.entry(ofType: type, forKey: key)
        // set back to memoryStorage
        memoryStorage.setObject(entry.object, forKey: key, expiry: entry.expiry)
        return entry
      }
    }
  }

  func removeObject(forKey key: String) throws {
    try lock.withLockUnchecked {
      memoryStorage.removeObject(forKey: key)
      try diskStorage.removeObject(forKey: key)
    }
  }

  func setObject<T: Codable & Sendable>(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
    try lock.withLockUnchecked {
      memoryStorage.setObject(object, forKey: key, expiry: expiry)
      try diskStorage.setObject(object, forKey: key, expiry: expiry)
    }
  }

  func removeAll() throws {
    try lock.withLockUnchecked {
      memoryStorage.removeAll()
      try diskStorage.removeAll()
    }
  }

  func removeExpiredObjects() throws {
    try lock.withLockUnchecked {
      memoryStorage.removeExpiredObjects()
      try diskStorage.removeExpiredObjects()
    }
  }
}
