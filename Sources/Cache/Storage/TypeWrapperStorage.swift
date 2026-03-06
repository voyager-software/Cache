import Foundation

/// Deal with top level primitive. Use TypeWrapper as wrapper
/// Because we use `JSONEncoder` and `JSONDecoder`.
/// Avoid issue like "Top-level T encoded as number JSON fragment"
final class TypeWrapperStorage: Sendable {
    // MARK: Lifecycle

    init(storage: StorageAware) {
        self.internalStorage = storage
    }

    // MARK: Internal

    let internalStorage: StorageAware
}

extension TypeWrapperStorage: StorageAware {
    func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
        let wrapperEntry = try internalStorage.entry(ofType: TypeWrapper<T>.self, forKey: key)
        return Entry(object: wrapperEntry.object.object, expiry: wrapperEntry.expiry)
    }

    func removeObject(forKey key: String) throws {
        try self.internalStorage.removeObject(forKey: key)
    }

    func setObject<T: Codable & Sendable>(_ object: T, forKey key: String,
                                          expiry: Expiry? = nil) throws
    {
        let wrapper = TypeWrapper<T>(object: object)
        try internalStorage.setObject(wrapper, forKey: key, expiry: expiry)
    }

    func removeAll() throws {
        try self.internalStorage.removeAll()
    }

    func removeExpiredObjects() throws {
        try self.internalStorage.removeExpiredObjects()
    }
}

/// Used to wrap Codable object
struct TypeWrapper<T: Codable & Sendable>: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case object
    }

    let object: T
}
