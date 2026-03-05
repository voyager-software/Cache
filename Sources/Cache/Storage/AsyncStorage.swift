import Foundation

/// Manipulate storage in an async manner.
/// All operations are dispatched to a serial queue for thread safety.
public final class AsyncStorage: Sendable {
  fileprivate let internalStorage: StorageAware
  fileprivate let serialQueue: DispatchQueue

  init(storage: StorageAware, serialQueue: DispatchQueue) {
    self.internalStorage = storage
    self.serialQueue = serialQueue
  }
}

extension AsyncStorage: AsyncStorageAware {
  public func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) async throws -> Entry<T> {
    try await withCheckedThrowingContinuation { continuation in
      serialQueue.async { [weak self] in
        guard let self else {
          continuation.resume(throwing: StorageError.deallocated)
          return
        }
        do {
          let anEntry: Entry<T> = try self.internalStorage.entry(ofType: type, forKey: key)
          continuation.resume(returning: anEntry)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func removeObject(forKey key: String) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      serialQueue.async { [weak self] in
        guard let self else {
          continuation.resume(throwing: StorageError.deallocated)
          return
        }
        do {
          try self.internalStorage.removeObject(forKey: key)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func setObject<T: Codable & Sendable>(_ object: T,
                                                forKey key: String,
                                                expiry: Expiry? = nil) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      serialQueue.async { [weak self] in
        guard let self else {
          continuation.resume(throwing: StorageError.deallocated)
          return
        }
        do {
          try self.internalStorage.setObject(object, forKey: key, expiry: expiry)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func removeAll() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      serialQueue.async { [weak self] in
        guard let self else {
          continuation.resume(throwing: StorageError.deallocated)
          return
        }
        do {
          try self.internalStorage.removeAll()
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func removeExpiredObjects() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      serialQueue.async { [weak self] in
        guard let self else {
          continuation.resume(throwing: StorageError.deallocated)
          return
        }
        do {
          try self.internalStorage.removeExpiredObjects()
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
