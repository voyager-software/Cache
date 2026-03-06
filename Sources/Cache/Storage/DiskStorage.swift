import Foundation
import os

/// Save objects to file on disk
final class DiskStorage: Sendable {
  private enum Error: Swift.Error {
    case fileEnumeratorFailed
  }

  /// File manager to read/write to the disk (access protected by lock)
  private nonisolated(unsafe) let fileManager: FileManager
  /// Configuration
  private let config: DiskConfig
  /// The computed path `directory+name`
  private let path: String
  /// Lock protecting all file I/O operations
  private let lock = OSAllocatedUnfairLock()

  // MARK: - Initialization

  required init(config: DiskConfig, fileManager: FileManager = FileManager.default) throws {
    self.config = config
    self.fileManager = fileManager

    let url: URL
    if let directory = config.directory {
      url = directory
    } else {
      url = try fileManager.url(
        for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      )
    }

    // path
    path = url.appendingPathComponent(config.name, isDirectory: true).path
    try createDirectory()

    // protection
    #if os(iOS) || os(tvOS)
      if let protectionType = config.protectionType {
        try setDirectoryAttributes([
          FileAttributeKey.protectionKey: protectionType
        ])
      }
    #endif
  }
}

extension DiskStorage: StorageAware {
  func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
    try lock.withLockUnchecked {
      let filePath = makeFilePath(for: key)
      let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
      let attributes = try fileManager.attributesOfItem(atPath: filePath)

      guard let date = attributes[.modificationDate] as? Date else {
        throw StorageError.malformedFileAttributes(key: key)
      }

      let meta: [String: any Sendable] = [
        "filePath": filePath
      ]

      let object: T
      if T.self == Data.self, let data = data as? T {
        object = data
      } else {
        object = try DataSerializer.deserialize(data: data)
      }

      return Entry(
        object: object,
        expiry: Expiry.date(date),
        meta: meta
      )
    }
  }

  func setObject<T: Codable & Sendable>(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
    try lock.withLockUnchecked {
      let expiry = expiry ?? config.expiry

      let data: Data
      if let rawData = object as? Data {
        data = rawData
      } else {
        data = try DataSerializer.serialize(object: object)
      }

      let filePath = makeFilePath(for: key)
      _ = fileManager.createFile(atPath: filePath, contents: data, attributes: nil)
      try fileManager.setAttributes([.modificationDate: expiry.date], ofItemAtPath: filePath)
    }
  }

  func removeObject(forKey key: String) throws {
    try lock.withLockUnchecked {
      try fileManager.removeItem(atPath: makeFilePath(for: key))
    }
  }

  func removeAll() throws {
    try lock.withLockUnchecked {
      try fileManager.removeItem(atPath: path)
      try createDirectory()
    }
  }

  func removeExpiredObjects() throws {
    try lock.withLockUnchecked {
      let storageURL = URL(fileURLWithPath: path)
      let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .contentModificationDateKey,
        .totalFileAllocatedSizeKey
      ]
      var resourceObjects = [ResourceObject]()
      var filesToDelete = [URL]()
      var totalSize: UInt = 0
      let fileEnumerator = fileManager.enumerator(
        at: storageURL,
        includingPropertiesForKeys: resourceKeys,
        options: .skipsHiddenFiles,
        errorHandler: nil
      )

      guard let urlArray = fileEnumerator?.allObjects as? [URL] else {
        throw Error.fileEnumeratorFailed
      }

      for url in urlArray {
        let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
        guard resourceValues.isDirectory != true else {
          continue
        }

        if let expiryDate = resourceValues.contentModificationDate, expiryDate.inThePast {
          filesToDelete.append(url)
          continue
        }

        if let fileSize = resourceValues.totalFileAllocatedSize {
          totalSize += UInt(fileSize)
          resourceObjects.append((url: url, resourceValues: resourceValues))
        }
      }

      // Remove expired objects
      for url in filesToDelete {
        try fileManager.removeItem(at: url)
      }

      // Remove objects if storage size exceeds max size
      try removeResourceObjects(resourceObjects, totalSize: totalSize)
    }
  }
}

private extension DiskStorage {
  typealias ResourceObject = (url: Foundation.URL, resourceValues: URLResourceValues)

  func setDirectoryAttributes(_ attributes: [FileAttributeKey: Any]) throws {
    try fileManager.setAttributes(attributes, ofItemAtPath: path)
  }

  /**
   Builds file name from the key.
   - Parameter key: Unique key to identify the object in the cache
   - Returns: A md5 string
   */
  func makeFileName(for key: String) -> String {
    return MD5.MD5(key)
  }

  /**
   Builds file path from the key.
   - Parameter key: Unique key to identify the object in the cache
   - Returns: A string path based on key
   */
  func makeFilePath(for key: String) -> String {
    return "\(path)/\(makeFileName(for: key))"
  }

  /// Calculates total disk cache size.
  func totalSize() throws -> UInt64 {
    try lock.withLockUnchecked {
      var size: UInt64 = 0
      let contents = try fileManager.contentsOfDirectory(atPath: path)
      for pathComponent in contents {
        let filePath = NSString(string: path).appendingPathComponent(pathComponent)
        let attributes = try fileManager.attributesOfItem(atPath: filePath)
        if let fileSize = attributes[.size] as? UInt64 {
          size += fileSize
        }
      }
      return size
    }
  }

  /// Creates the cache directory if it doesn't exist.
  /// Must be called while holding the lock, or during init.
  func createDirectory() throws {
    guard !fileManager.fileExists(atPath: path) else {
      return
    }

    try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true,
                                    attributes: nil)
  }

  /**
   Removes objects if storage size exceeds max size.
   Must be called while holding the lock.
   - Parameter objects: Resource objects to remove
   - Parameter totalSize: Total size
   */
  func removeResourceObjects(_ objects: [ResourceObject], totalSize: UInt) throws {
    guard config.maxSize > 0 && totalSize > config.maxSize else {
      return
    }

    var totalSize = totalSize
    let targetSize = config.maxSize / 2

    let sortedFiles = objects.sorted {
      if let time1 = $0.resourceValues.contentModificationDate?.timeIntervalSinceReferenceDate,
        let time2 = $1.resourceValues.contentModificationDate?.timeIntervalSinceReferenceDate {
        return time1 < time2
      } else {
        return false
      }
    }

    for file in sortedFiles {
      try fileManager.removeItem(at: file.url)
      if let fileSize = file.resourceValues.totalFileAllocatedSize {
        totalSize -= UInt(fileSize)
      }
      if totalSize < targetSize {
        break
      }
    }
  }

  /**
   Removes the object from the cache if it's expired.
   - Parameter key: Unique key to identify the object in the cache
   */
  func removeObjectIfExpired(forKey key: String) throws {
    try lock.withLockUnchecked {
      let filePath = makeFilePath(for: key)
      let attributes = try fileManager.attributesOfItem(atPath: filePath)
      if let expiryDate = attributes[.modificationDate] as? Date, expiryDate.inThePast {
        try fileManager.removeItem(atPath: filePath)
      }
    }
  }
}
