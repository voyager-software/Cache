import Foundation

/// What each kind of storage has to do. `Storage` documents the behaviour.
protocol StorageAware: Sendable {
    func object<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> T
    func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T>
    func removeObject(forKey key: String) throws
    func setObject(_ object: some Codable & Sendable, forKey key: String, expiry: Expiry?) throws
    func existsObject(forKey key: String) throws -> Bool
    func removeAll() throws
    func removeExpiredObjects() throws
    func diskSize() throws -> UInt64
}

extension StorageAware {
    func object<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> T {
        try entry(ofType: type, forKey: key).object
    }
}
