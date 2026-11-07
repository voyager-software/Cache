import Foundation
import os

/// Save objects to file on disk
final class DiskStorage: Sendable {
    // MARK: Lifecycle

    init(config: DiskConfig, fileManager: FileManager = FileManager.default) throws {
        // First, because the folder gets emptied later on, and these names could point at someone else's
        guard Self.isSingleFolderName(config.name) else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSFilePathErrorKey: config.name])
        }

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
        let path = url.appendingPathComponent(config.name, isDirectory: true).path
        // File system calls stop reading a path at a NUL, so they would act on a different folder.
        // The URL keeps a NUL as %00, which its path may or may not decode, so both are checked.
        guard url.isFileURL, !path.unicodeScalars.contains("\u{0}"),
              url.absoluteString.range(of: "%00", options: .caseInsensitive) == nil,
              URL(fileURLWithPath: path, isDirectory: true).lastPathComponent == config.name
        else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSFilePathErrorKey: path])
        }
        self.path = path
        try createDirectory()
    }

    // MARK: Internal

    /// Files in the current format end in this. A file named with just the hash was left by 4.x, whose
    /// format can't be read any more, so it's never looked up and `removeExpiredObjects()` removes it.
    static let fileExtension = "cache"

    /// Configuration
    let config: DiskConfig

    // MARK: Private

    private enum Error: Swift.Error {
        case fileEnumeratorFailed
    }

    /// File manager to read/write to the disk (access protected by lock)
    private nonisolated(unsafe) let fileManager: FileManager
    /// The computed path `directory+name`
    private let path: String
    /// Lock protecting all file I/O operations. Encoding and decoding stay outside of it, because
    /// they run the type's own code, which may be slow or use this storage.
    private let lock = OSAllocatedUnfairLock()
}

extension DiskStorage: StorageAware {
    func entry<T: Codable & Sendable>(ofType type: T.Type, forKey key: String) throws -> Entry<T> {
        let (data, date) = try self.lock.withLockUnchecked {
            let filePath = makeFilePath(for: key)
            do {
                // The expiry comes first, so that an expired object isn't read or decoded
                let attributes = try fileManager.attributesOfItem(atPath: filePath)
                guard let date = attributes[.modificationDate] as? Date else {
                    throw StorageError.malformedFileAttributes(key: key)
                }
                guard !date.inThePast else {
                    throw StorageError.notFound(key: key)
                }

                return (try Data(contentsOf: URL(fileURLWithPath: filePath)), date)
            }
            catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
                throw StorageError.notFound(key: key)
            }
        }

        let object: T = try decode(data, forKey: key)
        return Entry(object: object, expiry: Expiry.date(date))
    }

    func setObject<T: Codable & Sendable>(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
        try self.write(self.encode(object, forKey: key), forKey: key, expiry: expiry)
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

    /// Removes this storage's files one by one rather than the whole folder, so that a wrong path
    /// can't take anything else with it.
    func removeAll() throws {
        try self.lock.withLockUnchecked {
            var firstError: Swift.Error?

            for file in try listOwnFiles(keys: [], firstError: &firstError) {
                removeFile(at: file.url, firstError: &firstError)
            }
            try createDirectory()

            if let firstError {
                throw firstError
            }
        }
    }

    func removeExpiredObjects() throws {
        try self.lock.withLockUnchecked {
            var firstError: Swift.Error?

            for file in try listOwnFiles(keys: [.contentModificationDateKey], firstError: &firstError) {
                let isExpired = file.resourceValues.contentModificationDate?.inThePast ?? false
                if isExpired || file.url.pathExtension != Self.fileExtension {
                    removeFile(at: file.url, firstError: &firstError)
                }
            }

            if let firstError {
                throw firstError
            }
        }
    }

    func diskSize() throws -> UInt64 {
        try self.lock.withLockUnchecked {
            var firstError: Swift.Error?
            var size: UInt64 = 0

            for file in try listFiles(keys: [.totalFileAllocatedSizeKey], firstError: &firstError) {
                size += UInt64(file.resourceValues.totalFileAllocatedSize ?? 0)
            }

            if let firstError {
                throw firstError
            }
            return size
        }
    }
}

/// The two halves of `setObject`, so that hybrid storage can encode before taking its own lock.
extension DiskStorage {
    /// Wraps encoding failures in a `StorageError`, unless the type's own `Codable` code already threw one.
    func encode<T: Encodable>(_ object: T, forKey key: String) throws -> Data {
        // Exactly `Data`, like when reading. `as? Data` alone would also unwrap a `Data?`.
        if T.self == Data.self, let data = object as? Data {
            return data
        }

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

    func write(_ data: Data, forKey key: String, expiry: Expiry?) throws {
        try self.lock.withLockUnchecked {
            let expiry = expiry ?? self.config.expiry
            let filePath = makeFilePath(for: key)
            try writeFile(data, atPath: filePath)
            try self.fileManager.setAttributes([.modificationDate: expiry.date], ofItemAtPath: filePath)
        }
    }
}

private extension DiskStorage {
    /// Whether the name is one folder inside the directory, rather than the directory itself or a path out of it.
    /// Control characters are refused too: file system calls stop reading a path at a NUL.
    static func isSingleFolderName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
            && !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    /// Whether the file is named like one of this storage's objects: the key's hash, with the extension
    /// or without it like in 4.x. Nothing else is ever deleted, even if the folder holds other files.
    static func isOwnFileName(_ name: String) -> Bool {
        let suffix = ".\(Self.fileExtension)"
        let hash = name.hasSuffix(suffix) ? name.dropLast(suffix.count) : Substring(name)
        return hash.count == 32 && hash.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// Lists this storage's own files: directly in the cache folder, and named like its objects.
    /// Must be called while holding the lock.
    func listOwnFiles(keys: Set<URLResourceKey>,
                      firstError: inout Swift.Error?) throws -> [(url: URL, resourceValues: URLResourceValues)]
    {
        let folder = URL(fileURLWithPath: self.path, isDirectory: true).resolvingSymlinksInPath().path
        return try listFiles(keys: keys, firstError: &firstError).filter { file in
            Self.isOwnFileName(file.url.lastPathComponent)
                && file.url.deletingLastPathComponent().resolvingSymlinksInPath().path == folder
        }
    }

    /**
     Lists the files directly in the cache directory, hidden ones included, without looking inside folders.
     Keeps the first failure instead of stopping at it. A file that vanished during the scan is skipped.
     Must be called while holding the lock.
     - Parameter keys: The resource values that the caller needs
     - Parameter firstError: Keeps the first failure
     */
    func listFiles(keys: Set<URLResourceKey>,
                   firstError: inout Swift.Error?) throws -> [(url: URL, resourceValues: URLResourceValues)]
    {
        let resourceKeys = keys.union([.isDirectoryKey])
        var enumerationError: Swift.Error?
        let fileEnumerator = self.fileManager.enumerator(
            at: URL(fileURLWithPath: self.path),
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsSubdirectoryDescendants],
            errorHandler: { _, error in
                let code = (error as? CocoaError)?.code
                if code != .fileReadNoSuchFile, code != .fileNoSuchFile {
                    enumerationError = enumerationError ?? error
                }
                return true
            }
        )

        guard let urlArray = fileEnumerator?.allObjects as? [URL] else {
            throw Error.fileEnumeratorFailed
        }
        firstError = firstError ?? enumerationError

        var files = [(url: URL, resourceValues: URLResourceValues)]()
        for url in urlArray {
            let resourceValues: URLResourceValues
            do {
                resourceValues = try url.resourceValues(forKeys: resourceKeys)
            }
            catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
                continue
            }
            catch {
                firstError = firstError ?? error
                continue
            }

            if resourceValues.isDirectory != true {
                files.append((url: url, resourceValues: resourceValues))
            }
        }
        return files
    }

    /**
     Builds file name from the key.
     - Parameter key: Unique key to identify the object in the cache
     - Returns: A md5 string with the file extension
     */
    func makeFileName(for key: String) -> String {
        "\(MD5.hash(key)).\(Self.fileExtension)"
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

    /// Wraps decoding failures in a `StorageError`, unless the type's own `Codable` code already threw one.
    func decode<T: Decodable>(_ data: Data, forKey key: String) throws -> T {
        if T.self == Data.self, let data = data as? T {
            return data
        }

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
}
