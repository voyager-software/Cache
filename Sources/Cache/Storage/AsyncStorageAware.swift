import Foundation

/// A protocol used for saving and loading from storage in an async manner.
public protocol AsyncStorageAware: AnyObject, Sendable {
  /**
   Tries to retrieve the object from the storage.
   - Parameter type: The type to decode the object as.
   - Parameter key: Unique key to identify the object in the cache.
   - Returns: The cached object.
   */
  func object<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) async throws -> T

  /**
   Get cache entry which includes object with metadata.
   - Parameter type: The type to decode the object as.
   - Parameter key: Unique key to identify the object in the cache.
   - Returns: Object wrapper with metadata.
   */
  func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) async throws -> Entry<T>

  /**
   Removes the object by the given key.
   - Parameter key: Unique key to identify the object.
   */
  func removeObject(forKey key: String) async throws

  /**
   Saves passed object.
   - Parameter object: Object that needs to be cached.
   - Parameter key: Unique key to identify the object in the cache.
   - Parameter expiry: Overwrite expiry for this object only.
   */
  func setObject<T: Codable & Sendable>(_ object: T,
                                        forKey key: String,
                                        expiry: Expiry?) async throws

  /**
   Check if an object exists by the given key.
   - Parameter type: The type to decode the object as.
   - Parameter key: Unique key to identify the object.
   - Returns: Whether the object exists.
   */
  func existsObject<T: Codable & Sendable>(ofType type: T.Type,
                                           forKey key: String) async throws -> Bool

  /**
   Removes all objects from the cache storage.
   */
  func removeAll() async throws

  /**
   Clears all expired objects.
   */
  func removeExpiredObjects() async throws
}

public extension AsyncStorageAware {
  func object<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) async throws -> T {
    let anEntry: Entry<T> = try await entry(ofType: type, forKey: key)
    return anEntry.object
  }

  func existsObject<T: Codable & Sendable>(ofType type: T.Type,
                                           forKey key: String) async throws -> Bool {
    do {
      let _: T = try await object(ofType: type, forKey: key)
      return true
    } catch {
      return false
    }
  }
}
