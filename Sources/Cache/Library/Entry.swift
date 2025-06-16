import Foundation

/// A wrapper around cached object and its expiry date.
public struct Entry<T: Codable & Sendable>: Sendable {
  /// Cached object
  public let object: T
  /// Expiry date
  public let expiry: Expiry
  /// Associated meta data, if any
  public let meta: [String: any Sendable]

  init(object: T, expiry: Expiry, meta: [String: any Sendable] = [:]) {
    self.object = object
    self.expiry = expiry
    self.meta = meta
  }
}
