import Foundation

public enum StorageError: Error {
    /// Object can not be found
    case notFound(key: String)
    /// Object is found, but casting to requested type failed
    case typeNotMatch(key: String)
    /// The file attributes are malformed
    case malformedFileAttributes(key: String)
    /// The stored data can't be decoded as the requested type
    case decodingFailed(context: String, underlyingError: Error?)
    /// The object can't be encoded, or the encoded data can't be written to disk
    case encodingFailed(context: String, underlyingError: Error?)
}
