import Foundation
import Testing
@testable import Cache

@Suite("Storage")
struct StorageTests {
    // MARK: Round trips

    @Test("Reads back what was written", arguments: Sandbox.Mode.allCases)
    func roundTrip(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        let data = Data([0, 1, 2, 255])

        try storage.setObject(42, forKey: "int")
        try storage.setObject("text", forKey: "string")
        try storage.setObject(Person(name: "Ada"), forKey: "person")
        try storage.setObject(data, forKey: "data")

        #expect(try storage.object(ofType: Int.self, forKey: "int") == 42)
        #expect(try storage.object(ofType: String.self, forKey: "string") == "text")
        #expect(try storage.object(ofType: Person.self, forKey: "person") == Person(name: "Ada"))
        #expect(try storage.object(ofType: Data.self, forKey: "data") == data)
    }

    @Test("Data is stored as it is, with nothing around it")
    func dataIsStoredRaw() throws {
        let sandbox = try Sandbox()
        let data = Data(repeating: 7, count: 1000)

        try sandbox.storage(.disk).setObject(data, forKey: "key")

        let file = sandbox.folder().appendingPathComponent(fileName(for: "key"))
        #expect(try Data(contentsOf: file) == data)
    }

    @Test("Hybrid storage finds what an earlier instance saved")
    func hybridReadsFromDisk() throws {
        let sandbox = try Sandbox()
        try sandbox.storage(.hybrid).setObject("saved", forKey: "key")

        #expect(try sandbox.storage(.hybrid).object(ofType: String.self, forKey: "key") == "saved")
    }

    // MARK: Errors

    @Test("A miss throws notFound", arguments: Sandbox.Mode.allCases)
    func missThrowsNotFound(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)

        let error = try #require(throws: StorageError.self) {
            try storage.object(ofType: String.self, forKey: "missing")
        }
        guard case let .notFound(key) = error else {
            Issue.record("Expected notFound, got \(error)")
            return
        }
        #expect(key == "missing")
    }

    @Test("Asking for the wrong type on disk throws decodingFailed", arguments: [Sandbox.Mode.disk, .hybrid])
    func wrongTypeOnDisk(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject(1, forKey: "key")

        let error = try #require(throws: StorageError.self) {
            try storage.object(ofType: Person.self, forKey: "key")
        }
        guard case let .decodingFailed(_, underlying) = error else {
            Issue.record("Expected decodingFailed, got \(error)")
            return
        }
        #expect(underlying is DecodingError)
    }

    @Test("Asking for the wrong type in memory throws typeNotMatch")
    func wrongTypeInMemory() throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(.memory)
        try storage.setObject(1, forKey: "key")

        let error = try #require(throws: StorageError.self) {
            try storage.object(ofType: Person.self, forKey: "key")
        }
        guard case .typeNotMatch = error else {
            Issue.record("Expected typeNotMatch, got \(error)")
            return
        }
    }

    @Test("An encoding failure keeps its cause", arguments: [Sandbox.Mode.disk, .hybrid])
    func encodingFailureKeepsCause(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)

        let error = try #require(throws: StorageError.self) {
            try storage.setObject(Unencodable(), forKey: "key")
        }
        guard case let .encodingFailed(_, underlying) = error else {
            Issue.record("Expected encodingFailed, got \(error)")
            return
        }
        #expect(underlying is Unencodable.Failure)
    }

    @Test("A StorageError from a type's own Codable code isn't wrapped again")
    func storageErrorIsNotWrapped() throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(.disk)

        let error = try #require(throws: StorageError.self) {
            try storage.setObject(UnencodableWithStorageError(), forKey: "key")
        }
        guard case let .encodingFailed(context, _) = error else {
            Issue.record("Expected encodingFailed, got \(error)")
            return
        }
        #expect(context == "inner")
    }

    @Test("A failed write keeps its cause")
    func writeFailureKeepsCause() throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(.disk)
        // A file where the folder should be, which recreating the folder can't get around
        try FileManager.default.removeItem(at: sandbox.folder())
        try Data().write(to: sandbox.folder())

        let error = try #require(throws: StorageError.self) {
            try storage.setObject(1, forKey: "key")
        }
        guard case let .encodingFailed(_, underlying) = error else {
            Issue.record("Expected encodingFailed, got \(error)")
            return
        }
        #expect(underlying != nil)
    }

    // MARK: Failed writes

    @Test("A failed disk write leaves hybrid storage with the old value")
    func failedWriteKeepsOldValue() throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(.hybrid)
        try storage.setObject(1, forKey: "key")
        // A file where the folder should be, which recreating the folder can't get around
        try FileManager.default.removeItem(at: sandbox.folder())
        try Data().write(to: sandbox.folder())

        #expect(throws: StorageError.self) {
            try storage.setObject(2, forKey: "key")
        }

        #expect(try storage.object(ofType: Int.self, forKey: "key") == 1)
    }

    @Test("An object that can't be encoded doesn't end up in hybrid storage's memory")
    func failedEncodingLeavesMemoryAlone() throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(.hybrid)

        #expect(throws: StorageError.self) {
            try storage.setObject(Unencodable(), forKey: "key")
        }

        #expect(try storage.existsObject(forKey: "key") == false)
    }

    // MARK: Removing

    @Test("Removing a missing key succeeds", arguments: Sandbox.Mode.allCases)
    func removeMissingKey(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        try sandbox.storage(mode).removeObject(forKey: "missing")
    }

    @Test("Removing a key removes its object", arguments: Sandbox.Mode.allCases)
    func removeKey(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject(1, forKey: "key")

        try storage.removeObject(forKey: "key")

        #expect(try storage.existsObject(forKey: "key") == false)
    }

    @Test("removeAll removes everything and storage keeps working", arguments: Sandbox.Mode.allCases)
    func removeAll(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject(1, forKey: "a")

        try storage.removeAll()

        #expect(try storage.existsObject(forKey: "a") == false)
        try storage.setObject(2, forKey: "b")
        #expect(try storage.object(ofType: Int.self, forKey: "b") == 2)
    }

    // MARK: Expiry

    @Test("An expired object counts as missing, however it's asked for", arguments: Sandbox.Mode.allCases)
    func expiredObject(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject("old", forKey: "key", expiry: .seconds(-10))

        #expect(try storage.existsObject(forKey: "key") == false)
        for read in [
            { try storage.object(ofType: String.self, forKey: "key") },
            { try storage.entry(ofType: String.self, forKey: "key").object },
        ] {
            let error = try #require(throws: StorageError.self) {
                _ = try read()
            }
            guard case .notFound = error else {
                Issue.record("Expected notFound, got \(error)")
                return
            }
        }
    }

    @Test("An entry has the object and its expiry", arguments: Sandbox.Mode.allCases)
    func entryOfLiveObject(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        let expiry = Date().addingTimeInterval(3600)
        try storage.setObject("new", forKey: "key", expiry: .date(expiry))

        let entry = try storage.entry(ofType: String.self, forKey: "key")

        #expect(entry.object == "new")
        #expect(abs(entry.expiry.date.timeIntervalSince(expiry)) < 1)
    }

    @Test("removeExpiredObjects only removes expired objects", arguments: Sandbox.Mode.allCases)
    func removeExpiredObjects(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject("old", forKey: "old", expiry: .seconds(-10))
        try storage.setObject("new", forKey: "new", expiry: .seconds(3600))

        try storage.removeExpiredObjects()

        // Reads already treat an expired object as missing, so this has to look at the files
        if mode != .memory {
            #expect(try sandbox.files() == [fileName(for: "new")])
        }
        #expect(try storage.object(ofType: String.self, forKey: "new") == "new")
    }

    /// `.never` is stored as a far-future modification date, which the file system may clamp.
    @Test(".never survives on disk", arguments: [Sandbox.Mode.disk, .hybrid])
    func neverExpires(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject("kept", forKey: "key", expiry: .never)

        try storage.removeExpiredObjects()

        #expect(try sandbox.storage(mode).object(ofType: String.self, forKey: "key") == "kept")
    }

    // MARK: Files from older versions

    /// 4.x named files with just the hash, and wrapped each object in `{"object": ...}`.
    private func writeOldFormatFile(in sandbox: Sandbox, key: String) throws {
        let file = sandbox.folder().appendingPathComponent(MD5.hash(key))
        try Data(#"{"object":"old"}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date.distantFuture], ofItemAtPath: file.path)
    }

    @Test("A file from an older version is never read", arguments: [Sandbox.Mode.disk, .hybrid])
    func oldFormatIsNotRead(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try writeOldFormatFile(in: sandbox, key: "key")

        #expect(try storage.existsObject(forKey: "key") == false)
        let error = try #require(throws: StorageError.self) {
            try storage.object(ofType: String.self, forKey: "key")
        }
        guard case .notFound = error else {
            Issue.record("Expected notFound, got \(error)")
            return
        }
    }

    @Test("Purging removes files from older versions, even if they haven't expired")
    func purgeRemovesOldFormat() throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(.disk)
        try writeOldFormatFile(in: sandbox, key: "old")
        try storage.setObject("new", forKey: "new")

        try storage.removeExpiredObjects()

        #expect(try sandbox.files() == [fileName(for: "new")])
    }

    // MARK: Disk size

    @Test("diskSize follows what's on disk", arguments: [Sandbox.Mode.disk, .hybrid])
    func diskSize(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        #expect(try storage.diskSize() == 0)

        try storage.setObject(Data(repeating: 1, count: 5000), forKey: "key")
        #expect(try storage.diskSize() >= 5000)

        try storage.removeAll()
        #expect(try storage.diskSize() == 0)
    }

    @Test("diskSize is 0 without a disk, or without the folder")
    func diskSizeWithoutDisk() throws {
        let sandbox = try Sandbox()
        let memory = try sandbox.storage(.memory)
        try memory.setObject(1, forKey: "key")
        #expect(try memory.diskSize() == 0)

        let disk = try sandbox.storage(.disk)
        try FileManager.default.removeItem(at: sandbox.folder())
        #expect(try disk.diskSize() == 0)
    }

    // MARK: Losing the folder

    @Test("Writing brings back a folder that was deleted", arguments: [Sandbox.Mode.disk, .hybrid])
    func writeRecreatesFolder(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject(1, forKey: "a")
        try FileManager.default.removeItem(at: sandbox.folder())

        try storage.setObject(2, forKey: "b")

        #expect(try sandbox.files().count == 1)
        #expect(try storage.object(ofType: Int.self, forKey: "b") == 2)
    }

    @Test("removeAll works when the folder was deleted, and brings it back", arguments: [Sandbox.Mode.disk, .hybrid])
    func removeAllRecreatesFolder(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try FileManager.default.removeItem(at: sandbox.folder())

        try storage.removeAll()

        #expect(try sandbox.files().isEmpty)
    }

    @Test("Reading and purging are fine when the folder was deleted", arguments: [Sandbox.Mode.disk, .hybrid])
    func readsWithoutFolder(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try FileManager.default.removeItem(at: sandbox.folder())

        try storage.removeExpiredObjects()
        #expect(try storage.existsObject(forKey: "key") == false)
        #expect(throws: StorageError.self) {
            try storage.object(ofType: Int.self, forKey: "key")
        }
    }
}

@Suite("MemoryStorage")
struct MemoryStorageTests {
    @Test("Purging forgets the keys of objects NSCache has evicted")
    func forgetsEvictedKeys() {
        let storage = MemoryStorage(config: MemoryConfig())
        // What eviction leaves behind: a tracked key with no object. Set up by hand, because
        // NSCache decides for itself when to evict.
        storage.lockedKeys.withLock { _ = $0.insert("evicted") }

        storage.removeExpiredObjects()

        #expect(storage.lockedKeys.withLock { $0 }.isEmpty)
    }

    @Test("Purging keeps the keys of objects that are still there")
    func keepsLiveKeys() throws {
        let storage = MemoryStorage(config: MemoryConfig())
        storage.setObject(1, forKey: "kept", expiry: .never)
        storage.setObject(2, forKey: "old", expiry: .seconds(-10))

        storage.removeExpiredObjects()

        #expect(storage.lockedKeys.withLock { $0 } == ["kept"])
        #expect(try storage.object(ofType: Int.self, forKey: "kept") == 1)
    }
}

/// Runs a hook before each removal, which can fail it or delete the file first.
private final class HookedFileManager: FileManager, @unchecked Sendable {
    var beforeRemoving: (String) throws -> Void = { _ in }

    override func removeItem(atPath path: String) throws {
        try self.beforeRemoving(path)
        try super.removeItem(atPath: path)
    }

    override func removeItem(at url: URL) throws {
        try self.beforeRemoving(url.path)
        try super.removeItem(at: url)
    }
}

@Suite("Purging with failures")
struct PurgeFailureTests {
    struct RemovalFailed: Error {}

    @Test("A file that can't be removed doesn't stop the others, and the failure is still thrown")
    func continuesPastFailure() throws {
        let sandbox = try Sandbox()
        let fileManager = HookedFileManager()
        let storage = try DiskStorage(config: DiskConfig(name: "cache", directory: sandbox.root), fileManager: fileManager)
        for key in ["a", "b", "c"] {
            try storage.setObject(1, forKey: key, expiry: .seconds(-10))
        }
        // Whichever file comes first, so that stopping at the failure would leave the others behind
        var failedFile: String?
        fileManager.beforeRemoving = { path in
            if failedFile == nil {
                failedFile = URL(fileURLWithPath: path).lastPathComponent
            }
            if URL(fileURLWithPath: path).lastPathComponent == failedFile {
                throw RemovalFailed()
            }
        }

        #expect(throws: RemovalFailed.self) {
            try storage.removeExpiredObjects()
        }

        #expect(try sandbox.files() == [try #require(failedFile)])
    }

    @Test("A file that vanishes during the purge isn't a failure")
    func vanishedFileIsFine() throws {
        let sandbox = try Sandbox()
        let fileManager = HookedFileManager()
        let storage = try DiskStorage(config: DiskConfig(name: "cache", directory: sandbox.root), fileManager: fileManager)
        for key in ["a", "b", "c"] {
            try storage.setObject(1, forKey: key, expiry: .seconds(-10))
        }
        fileManager.beforeRemoving = { path in
            if path.hasSuffix(fileName(for: "b")), FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }

        try storage.removeExpiredObjects()

        #expect(try sandbox.files().isEmpty)
    }
}

#if os(iOS) || os(tvOS)
/// The Simulator doesn't report file protection back, so this looks at what's asked for instead.
private final class RecordingFileManager: FileManager, @unchecked Sendable {
    var protections = [FileProtectionType]()

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            self.protections.append(protection)
        }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }
}

@Suite("File protection")
struct FileProtectionTests {
    @Test("Applied when opened, and whenever the folder comes back")
    func reappliedWithFolder() throws {
        let sandbox = try Sandbox()
        let fileManager = RecordingFileManager()
        let config = DiskConfig(name: "cache", directory: sandbox.root, protectionType: .complete)
        let storage = try DiskStorage(config: config, fileManager: fileManager)
        #expect(fileManager.protections == [.complete])

        fileManager.protections = []
        try storage.setObject(1, forKey: "a", expiry: nil)
        #expect(fileManager.protections.isEmpty)

        try storage.removeAll()
        #expect(fileManager.protections == [.complete])

        fileManager.protections = []
        try FileManager.default.removeItem(at: sandbox.folder())
        try storage.setObject(2, forKey: "b", expiry: nil)
        #expect(fileManager.protections == [.complete])
    }
}
#endif
