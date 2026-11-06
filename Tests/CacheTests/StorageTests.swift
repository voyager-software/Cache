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

    @Test("An expired object counts as missing, but its entry can still be read", arguments: Sandbox.Mode.allCases)
    func expiredObject(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject("old", forKey: "key", expiry: .seconds(-10))

        #expect(throws: StorageError.self) {
            try storage.object(ofType: String.self, forKey: "key")
        }
        #expect(try storage.existsObject(forKey: "key") == false)

        let entry = try storage.entry(ofType: String.self, forKey: "key")
        #expect(entry.object == "old")
        #expect(entry.expiry.isExpired)
    }

    @Test("removeExpiredObjects only removes expired objects", arguments: Sandbox.Mode.allCases)
    func removeExpiredObjects(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject("old", forKey: "old", expiry: .seconds(-10))
        try storage.setObject("new", forKey: "new", expiry: .seconds(3600))

        try storage.removeExpiredObjects()

        #expect(throws: StorageError.self) {
            try storage.entry(ofType: String.self, forKey: "old")
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

    @Test("Going over maxSize evicts the soonest to expire first")
    func eviction() throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(.disk, maxSize: 40000)
        let blob = Data(repeating: 1, count: 5000)
        try storage.setObject(blob, forKey: "never", expiry: .never)
        for minutes in 1 ... 4 {
            try storage.setObject(blob, forKey: "\(minutes)", expiry: .seconds(Double(minutes) * 60))
        }
        try storage.setObject(blob, forKey: "latest", expiry: .seconds(6000))

        try storage.removeExpiredObjects()

        #expect(try storage.existsObject(forKey: "1") == false)
        #expect(try storage.existsObject(forKey: "never"))
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
        let storage = MemoryStorage(config: MemoryConfig(countLimit: 10))
        for index in 0 ..< 1000 {
            storage.setObject(index, forKey: "key-\(index)", expiry: .never)
        }
        #expect(storage.lockedKeys.withLock { $0.count } == 1000)

        storage.removeExpiredObjects()

        // NSCache treats its limit as a guide, so this doesn't ask for exactly 10
        #expect(storage.lockedKeys.withLock { $0.count } < 100)
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
