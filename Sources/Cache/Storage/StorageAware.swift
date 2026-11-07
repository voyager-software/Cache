import Foundation

/// A protocol used for saving and loading from storage
public protocol StorageAware: Sendable {
    /**
     Tries to retrieve the object from the storage.
     - Parameter key: Unique key to identify the object in the cache
     - Returns: Cached object
     - Throws: `StorageError.notFound` if there's no object for the key, or it has expired
     */
    func object<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> T

    /**
     Get cache entry which includes object with metadata.
     Unlike `object(ofType:forKey:)`, this also returns an expired object, so check `expiry.isExpired`.
     - Parameter key: Unique key to identify the object in the cache
     - Returns: Object wrapper with metadata
     - Throws: `StorageError.notFound` if there's no object for the key
     */
    func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T>

    /**
     Removes the object by the given key. Does nothing if there's no object for the key.
     - Parameter key: Unique key to identify the object.
     */
    func removeObject(forKey key: String) throws

    /**
     Saves passed object.
     - Parameter key: Unique key to identify the object in the cache.
     - Parameter object: Object that needs to be cached.
     - Parameter expiry: Overwrite expiry for this object only.
     */
    func setObject(_ object: some Codable & Sendable, forKey key: String, expiry: Expiry?) throws

    /**
     Check if a non-expired object exists for the given key.
     Does not read the object, so a read can still fail after this returns `true`, for example
     for a file with `.complete` protection while the device is locked.
     - Parameter key: Unique key to identify the object.
     */
    func existsObject(forKey key: String) throws -> Bool

    /**
     Removes all objects from the cache storage.
     */
    func removeAll() throws

    /**
     Clears all expired objects, and enforces `DiskConfig.maxSize`.
     A file that can't be removed doesn't stop the others. The first failure is thrown at the end.
     */
    func removeExpiredObjects() throws

}

public extension StorageAware {
    func object<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> T {
        let entry = try entry(ofType: type, forKey: key)
        guard !entry.expiry.isExpired else {
            throw StorageError.notFound(key: key)
        }
        return entry.object
    }
}
