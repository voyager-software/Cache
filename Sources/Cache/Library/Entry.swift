import Foundation

/// A wrapper around cached object and its expiry date.
public struct Entry<T: Codable & Sendable>: Sendable {
    // MARK: Lifecycle

    init(object: T, expiry: Expiry) {
        self.object = object
        self.expiry = expiry
    }

    // MARK: Public

    /// Cached object
    public let object: T
    /// Expiry date
    public let expiry: Expiry
}
