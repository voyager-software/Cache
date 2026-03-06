import Foundation
import os

/// Save objects to file on disk
final class DiskStorage: Sendable {
    // MARK: Lifecycle

    init(config: DiskConfig, fileManager: FileManager = FileManager.default) throws {
        self.config = config
        self.fileManager = fileManager

        let url: URL = if let directory = config.directory {
            directory
        }
        else {
            try fileManager.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
        }

        // path
        self.path = url.appendingPathComponent(config.name, isDirectory: true).path
        try createDirectory()

        // protection
        #if os(iOS) || os(tvOS)
        if let protectionType = config.protectionType {
            try setDirectoryAttributes([
                FileAttributeKey.protectionKey: protectionType,
            ])
        }
        #endif
    }

    // MARK: Private

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
}

extension DiskStorage: StorageAware {
    func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
        try self.lock.withLockUnchecked {
            let filePath = makeFilePath(for: key)
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let attributes = try fileManager.attributesOfItem(atPath: filePath)

            guard let date = attributes[.modificationDate] as? Date else {
                throw StorageError.malformedFileAttributes(key: key)
            }

            let meta: [String: any Sendable] = [
                "filePath": filePath,
            ]

            let object: T = if T.self == Data.self, let data = data as? T {
                data
            }
            else {
                try DataSerializer.deserialize(data: data)
            }

            return Entry(
                object: object,
                expiry: Expiry.date(date),
                meta: meta
            )
        }
    }

    func setObject(_ object: some Codable & Sendable, forKey key: String, expiry: Expiry? = nil) throws {
        try self.lock.withLockUnchecked {
            let expiry = expiry ?? self.config.expiry

            let data: Data = if let rawData = object as? Data {
                rawData
            }
            else {
                try DataSerializer.serialize(object: object)
            }

            let filePath = makeFilePath(for: key)
            guard self.fileManager.createFile(atPath: filePath, contents: data, attributes: nil) else {
                throw StorageError.encodingFailed(context: "DiskStorage: failed to write data to path: \(filePath)", underlyingError: nil)
            }
            try self.fileManager.setAttributes([.modificationDate: expiry.date], ofItemAtPath: filePath)
        }
    }

    func removeObject(forKey key: String) throws {
        try self.lock.withLockUnchecked {
            try self.fileManager.removeItem(atPath: makeFilePath(for: key))
        }
    }

    func removeAll() throws {
        try self.lock.withLockUnchecked {
            try self.fileManager.removeItem(atPath: self.path)
            try createDirectory()
        }
    }

    func removeExpiredObjects() throws {
        try self.lock.withLockUnchecked {
            let storageURL = URL(fileURLWithPath: path)
            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .contentModificationDateKey,
                .totalFileAllocatedSizeKey,
            ]
            var resourceObjects = [ResourceObject]()
            var filesToDelete = [URL]()
            var totalSize: UInt = 0
            let fileEnumerator = self.fileManager.enumerator(
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
                try self.fileManager.removeItem(at: url)
            }

            // Remove objects if storage size exceeds max size
            try removeResourceObjects(resourceObjects, totalSize: totalSize)
        }
    }
}

private extension DiskStorage {
    typealias ResourceObject = (url: Foundation.URL, resourceValues: URLResourceValues)

    func setDirectoryAttributes(_ attributes: [FileAttributeKey: Any]) throws {
        try self.fileManager.setAttributes(attributes, ofItemAtPath: self.path)
    }

    /**
     Builds file name from the key.
     - Parameter key: Unique key to identify the object in the cache
     - Returns: A md5 string
     */
    func makeFileName(for key: String) -> String {
        MD5.hash(key)
    }

    /**
     Builds file path from the key.
     - Parameter key: Unique key to identify the object in the cache
     - Returns: A string path based on key
     */
    func makeFilePath(for key: String) -> String {
        "\(self.path)/\(self.makeFileName(for: key))"
    }

    /// Creates the cache directory if it doesn't exist.
    /// Must be called while holding the lock, or during init.
    func createDirectory() throws {
        guard !self.fileManager.fileExists(atPath: self.path) else {
            return
        }

        try self.fileManager.createDirectory(atPath: self.path, withIntermediateDirectories: true,
                                             attributes: nil)
    }

    /**
     Removes objects if storage size exceeds max size.
     Must be called while holding the lock.
     - Parameter objects: Resource objects to remove
     - Parameter totalSize: Total size
     */
    func removeResourceObjects(_ objects: [ResourceObject], totalSize: UInt) throws {
        guard self.config.maxSize > 0, totalSize > self.config.maxSize else {
            return
        }

        var remainingSize = totalSize
        let targetSize = self.config.maxSize / 2

        let sortedFiles = objects.sorted {
            if let time1 = $0.resourceValues.contentModificationDate?.timeIntervalSinceReferenceDate,
               let time2 = $1.resourceValues.contentModificationDate?.timeIntervalSinceReferenceDate
            {
                time1 < time2
            }
            else {
                false
            }
        }

        for file in sortedFiles {
            try self.fileManager.removeItem(at: file.url)
            if let fileSize = file.resourceValues.totalFileAllocatedSize {
                remainingSize -= UInt(fileSize)
            }
            if remainingSize < targetSize {
                break
            }
        }
    }
}
