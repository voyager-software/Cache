import Foundation

public enum StorageError: Error {
  /// Object can not be found
  case notFound(key: String)
  /// Object is found, but casting to requested type failed
  case typeNotMatch(key: String)
  /// The file attributes are malformed
  case malformedFileAttributes(key: String)
  /// Can't perform Decode
  case decodingFailed(context: String, underlyingError: Error?)
  /// Can't perform Encode
  case encodingFailed(context: String, underlyingError: Error?)
}
