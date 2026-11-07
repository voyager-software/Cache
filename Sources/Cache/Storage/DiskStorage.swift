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
            let data: Data
            do {
                data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            }
            catch CocoaError.fileReadNoSuchFile {
                throw StorageError.notFound(key: key)
            }
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
                try decode(data, forKey: key)
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
                try encode(object, forKey: key)
            }

            let filePath = makeFilePath(for: key)
            try writeFile(data, atPath: filePath)
            try self.fileManager.setAttributes([.modificationDate: expiry.date], ofItemAtPath: filePath)
        }
    }

    func existsObject(forKey key: String) throws -> Bool {
        try lock.withLockUnchecked {
            let filePath = makeFilePath(for: key)
            guard fileManager.fileExists(atPath: filePath) else {
                return false
            }
            let attributes = try fileManager.attributesOfItem(atPath: filePath)
            guard let date = attributes[.modificationDate] as? Date else {
                return false
            }
            return !date.inThePast
        }
    }

    func removeObject(forKey key: String) throws {
        try self.lock.withLockUnchecked {
            try removeItemIfPresent(atPath: makeFilePath(for: key))
        }
    }

    func removeAll() throws {
        try self.lock.withLockUnchecked {
            try removeItemIfPresent(atPath: self.path)
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
            var filesToDelete = [ResourceObject]()
            var totalSize: UInt = 0
            var firstError: Swift.Error?
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
                let resourceValues: URLResourceValues
                do {
                    resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                }
                catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
                    // A file that vanished during the scan doesn't need cleaning up
                    continue
                }
                catch {
                    firstError = firstError ?? error
                    continue
                }

                guard resourceValues.isDirectory != true else {
                    continue
                }

                if let expiryDate = resourceValues.contentModificationDate, expiryDate.inThePast {
                    filesToDelete.append((url: url, resourceValues: resourceValues))
                    continue
                }

                if let fileSize = resourceValues.totalFileAllocatedSize {
                    totalSize += UInt(fileSize)
                    resourceObjects.append((url: url, resourceValues: resourceValues))
                }
            }

            // Remove expired objects
            for file in filesToDelete {
                // A file that couldn't be removed still takes up space, so it counts toward the max size
                if !removeFile(at: file.url, firstError: &firstError), let fileSize = file.resourceValues.totalFileAllocatedSize {
                    totalSize += UInt(fileSize)
                }
            }

            // Remove objects if storage size exceeds max size
            removeResourceObjects(resourceObjects, totalSize: totalSize, firstError: &firstError)

            if let firstError {
                throw firstError
            }
        }
    }
}

private extension DiskStorage {
    typealias ResourceObject = (url: Foundation.URL, resourceValues: URLResourceValues)

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

    /// Creates the cache directory if it doesn't exist, and applies the configured file protection.
    /// Must be called while holding the lock, or during init.
    func createDirectory() throws {
        if !self.fileManager.fileExists(atPath: self.path) {
            try self.fileManager.createDirectory(atPath: self.path, withIntermediateDirectories: true,
                                                 attributes: nil)
        }

        #if os(iOS) || os(tvOS)
        if let protectionType = self.config.protectionType {
            try self.fileManager.setAttributes([.protectionKey: protectionType], ofItemAtPath: self.path)
        }
        #endif
    }

    /// Writes the file, bringing the cache directory back first if it's gone. The system can purge
    /// the Caches directory while the app is running.
    /// Must be called while holding the lock.
    func writeFile(_ data: Data, atPath filePath: String) throws {
        let url = URL(fileURLWithPath: filePath)
        do {
            do {
                try data.write(to: url, options: .atomic)
            }
            catch CocoaError.fileNoSuchFile {
                try createDirectory()
                try data.write(to: url, options: .atomic)
            }
        }
        catch {
            throw StorageError.encodingFailed(context: "DiskStorage: failed to write data to path: \(filePath)", underlyingError: error)
        }
    }

    /// Removes the item, and does nothing if it's already gone.
    /// Must be called while holding the lock.
    func removeItemIfPresent(atPath path: String) throws {
        do {
            try self.fileManager.removeItem(atPath: path)
        }
        catch CocoaError.fileNoSuchFile {}
    }

    /// Removes the file, keeping the first failure instead of stopping at it.
    /// Must be called while holding the lock.
    /// - Returns: Whether the file is gone
    @discardableResult
    func removeFile(at url: URL, firstError: inout Swift.Error?) -> Bool {
        do {
            try removeItemIfPresent(atPath: url.path)
            return true
        }
        catch {
            firstError = firstError ?? error
            return false
        }
    }

    /// Wraps encoding failures in a `StorageError`, unless the type's own `Codable` code already threw one.
    func encode(_ object: some Encodable, forKey key: String) throws -> Data {
        do {
            return try DataSerializer.serialize(object: object)
        }
        catch let error as StorageError {
            throw error
        }
        catch {
            throw StorageError.encodingFailed(context: "DiskStorage: failed to encode object for key: \(key)", underlyingError: error)
        }
    }

    /// Wraps decoding failures in a `StorageError`, unless the type's own `Codable` code already threw one.
    func decode<T: Decodable>(_ data: Data, forKey key: String) throws -> T {
        do {
            return try DataSerializer.deserialize(data: data)
        }
        catch let error as StorageError {
            throw error
        }
        catch {
            throw StorageError.decodingFailed(context: "DiskStorage: failed to decode object for key: \(key)", underlyingError: error)
        }
    }

    /**
     Removes objects if storage size exceeds max size.
     Must be called while holding the lock.
     - Parameter objects: Resource objects to remove
     - Parameter totalSize: Total size
     - Parameter firstError: Keeps the first failure, so that the other objects still get removed
     */
    func removeResourceObjects(_ objects: [ResourceObject], totalSize: UInt, firstError: inout Swift.Error?) {
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
            guard removeFile(at: file.url, firstError: &firstError) else {
                continue
            }
            if let fileSize = file.resourceValues.totalFileAllocatedSize {
                remainingSize -= UInt(fileSize)
            }
            if remainingSize < targetSize {
                break
            }
        }
    }
}
