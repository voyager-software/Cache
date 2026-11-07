import Foundation
import Testing
@testable import Cache

/// What a read came to, in a form that can be compared between kinds of storage.
enum ReadOutcome: Hashable {
    /// The value as JSON, which shows the bytes of a `Data` too
    case value(String)
    case notFound
    /// `typeNotMatch` from memory and `decodingFailed` from disk mean the same thing to the caller
    case wrongType
    case otherError(String)
}

/// Writes a value, and reads it back as some type.
struct ReadCase: Sendable, CustomTestStringConvertible {
    // MARK: Internal

    let testDescription: String
    let write: @Sendable (Storage) throws -> Void
    let read: @Sendable (Storage) throws -> String
    let expected: ReadOutcome?

    /// Written and read as the same type, which must give back the same value.
    static func same<T: Codable & Sendable>(_ value: T, _ name: String = "\(T.self)") -> ReadCase {
        ReadCase(testDescription: name, write: self.writing(value), read: self.reading(T.self),
                 expected: .value(self.json(value)))
    }

    /// Read as a type that doesn't fit what was written.
    static func mismatch<T: Codable & Sendable, U: Codable & Sendable>(_ value: T, as _: U.Type) -> ReadCase {
        ReadCase(testDescription: "\(T.self) as \(U.self)", write: self.writing(value), read: self.reading(U.self),
                 expected: .wrongType)
    }

    /// Read as a different type, where the kinds of storage are known to disagree.
    static func disagreeing<T: Codable & Sendable, U: Codable & Sendable>(_ value: T, as _: U.Type) -> ReadCase {
        ReadCase(testDescription: "\(T.self) as \(U.self)", write: self.writing(value), read: self.reading(U.self),
                 expected: nil)
    }

    // MARK: Private

    private static func writing(_ value: some Codable & Sendable) -> @Sendable (Storage) throws -> Void {
        { try $0.setObject(value, forKey: "key") }
    }

    private static func reading<T: Codable & Sendable>(_: T.Type) -> @Sendable (Storage) throws -> String {
        { try self.json($0.object(ofType: T.self, forKey: "key")) }
    }

    private static func json(_ value: some Encodable) -> String {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "can't be encoded"
    }
}

/// Every way of reading: from the instance that wrote the object, which for hybrid means from
/// memory, and from a new instance, which for disk and hybrid means from the file.
private func outcomes(of readCase: ReadCase) throws -> [String: ReadOutcome] {
    var outcomes = [String: ReadOutcome]()
    for (mode, reopened) in [(Sandbox.Mode.disk, true), (.memory, false), (.hybrid, false), (.hybrid, true)] {
        let sandbox = try Sandbox()
        let writer = try sandbox.storage(mode)
        try readCase.write(writer)
        let reader = reopened ? try sandbox.storage(mode) : writer

        let name = "\(mode)\(reopened ? " reopened" : "")"
        do {
            outcomes[name] = try .value(readCase.read(reader))
        }
        catch StorageError.notFound {
            outcomes[name] = .notFound
        }
        catch StorageError.typeNotMatch, StorageError.decodingFailed {
            outcomes[name] = .wrongType
        }
        catch {
            outcomes[name] = .otherError("\(error)")
        }
    }
    return outcomes
}

@Suite("All kinds of storage agree")
struct ParityTests {
    static let sameTypeCases: [ReadCase] = [
        .same(42),
        .same(-1.5),
        .same(true),
        .same("text"),
        .same(""),
        .same(Date(timeIntervalSince1970: 1000)),
        .same(Person(name: "Ada")),
        .same([1, 2, 3]),
        .same(["a": 1]),
        .same(Data([0, 255, 254, 1]), "Data"),
        .same(Data(), "empty Data"),
        .same([Data([0, 255])]),
        .same(Data?(Data([0, 255, 254, 1])), "Data? with a value"),
        .same(Data?.none, "Data? without a value"),
        .same(Int?(1), "Int? with a value"),
        .same(Int?.none, "Int? without a value"),
    ]

    static let mismatchCases: [ReadCase] = [
        .mismatch(1, as: Person.self),
        .mismatch("text", as: Int.self),
        .mismatch(Person(name: "Ada"), as: String.self),
        .mismatch(Int?.none, as: Int.self),
    ]

    /// Files don't record the type they were written with. `Data` is read as it is without looking
    /// inside, and anything else is decoded if its JSON happens to fit, while memory compares types.
    /// The README tells callers to read with the type they wrote. If one of these starts passing,
    /// that's good news: move it up to `sameTypeCases` or `mismatchCases`.
    static let disagreeingCases: [ReadCase] = [
        .disagreeing(Data?(Data([0, 255])), as: Data.self),
        .disagreeing(Data([0, 255]), as: Data?.self),
        .disagreeing(Person(name: "Ada"), as: Data.self),
        .disagreeing(1, as: Double.self),
    ]

    @Test("Reading with the type that was written gives back the value", arguments: sameTypeCases)
    func sameType(readCase: ReadCase) throws {
        for (reader, outcome) in try outcomes(of: readCase) {
            #expect(outcome == readCase.expected, "Read by \(reader)")
        }
    }

    @Test("Reading with a type that doesn't fit is an error", arguments: mismatchCases)
    func mismatch(readCase: ReadCase) throws {
        for (reader, outcome) in try outcomes(of: readCase) {
            #expect(outcome == readCase.expected, "Read by \(reader)")
        }
    }

    @Test("Reading with another type that happens to fit depends on the storage", arguments: disagreeingCases)
    func knownDisagreement(readCase: ReadCase) throws {
        let results = try outcomes(of: readCase)
        withKnownIssue("Files don't record the type they were written with") {
            #expect(Set(results.values).count == 1, "\(results)")
        }
    }

    // MARK: The config's default expiry

    @Test("The config's expiry applies when an object has none of its own", arguments: Sandbox.Mode.allCases)
    func configExpiry(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode, expiry: .seconds(-10))

        try storage.setObject(1, forKey: "key")

        #expect(try storage.existsObject(forKey: "key") == false)
        #expect(throws: StorageError.self) {
            try storage.object(ofType: Int.self, forKey: "key")
        }
    }

    @Test("The config's expiry is reported in the entry", arguments: Sandbox.Mode.allCases)
    func configExpiryInEntry(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode, expiry: .seconds(3600))

        try storage.setObject(1, forKey: "key")

        let expiry = try storage.entry(ofType: Int.self, forKey: "key").expiry.date
        #expect(abs(expiry.timeIntervalSinceNow - 3600) < 60)
    }

    @Test("An object's own expiry beats an expired config", arguments: Sandbox.Mode.allCases)
    func objectExpiryOverridesExpiredConfig(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode, expiry: .seconds(-10))

        try storage.setObject(1, forKey: "key", expiry: .seconds(3600))

        #expect(try storage.object(ofType: Int.self, forKey: "key") == 1)
    }

    @Test("An object's own expiry beats a config that never expires", arguments: Sandbox.Mode.allCases)
    func objectExpiryOverridesLastingConfig(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode, expiry: .never)

        try storage.setObject(1, forKey: "key", expiry: .seconds(-10))

        #expect(try storage.existsObject(forKey: "key") == false)
    }
}

@Suite("Hybrid storage's expiry")
struct HybridExpiryTests {
    private func makeStorage(in sandbox: Sandbox, disk: Expiry, memory: Expiry) throws -> Storage {
        try Storage(diskConfig: DiskConfig(name: "cache", expiry: disk, directory: sandbox.root),
                    memoryConfig: MemoryConfig(expiry: memory))
    }

    @Test("The copy in memory doesn't outlive the file")
    func memoryDoesNotOutliveDisk() throws {
        let sandbox = try Sandbox()
        let storage = try makeStorage(in: sandbox, disk: .seconds(-10), memory: .never)

        try storage.setObject("stale", forKey: "key")

        #expect(try storage.existsObject(forKey: "key") == false)
        #expect(throws: StorageError.self) {
            try storage.object(ofType: String.self, forKey: "key")
        }
    }

    @Test("MemoryConfig's expiry doesn't cut an object short")
    func memoryExpiryIsNotUsed() throws {
        let sandbox = try Sandbox()
        let storage = try makeStorage(in: sandbox, disk: .never, memory: .seconds(-10))

        try storage.setObject("kept", forKey: "key")

        #expect(try storage.object(ofType: String.self, forKey: "key") == "kept")
    }

    @Test("An entry reports the same expiry from memory and from disk")
    func sameExpiryFromMemoryAndDisk() throws {
        let sandbox = try Sandbox()
        let writer = try makeStorage(in: sandbox, disk: .seconds(3600), memory: .seconds(60))
        try writer.setObject("value", forKey: "key")

        let fromMemory = try writer.entry(ofType: String.self, forKey: "key").expiry.date
        let reader = try makeStorage(in: sandbox, disk: .seconds(3600), memory: .seconds(60))
        let fromDisk = try reader.entry(ofType: String.self, forKey: "key").expiry.date
        let refilled = try reader.entry(ofType: String.self, forKey: "key").expiry.date

        #expect(abs(fromMemory.timeIntervalSince(fromDisk)) < 1)
        #expect(abs(fromDisk.timeIntervalSince(refilled)) < 1)
        #expect(abs(fromDisk.timeIntervalSinceNow - 3600) < 60)
    }
}

@Suite("Folder names")
struct FolderNameTests {
    @Test("A name that isn't a single folder is refused, with nothing touched",
          arguments: ["", ".", "..", "../escaped", "a/b", "/absolute", "a/"])
    func refused(name: String) throws {
        let sandbox = try Sandbox()
        let bystander = sandbox.root.appendingPathComponent("bystander.txt")
        try Data([1]).write(to: bystander)

        let error = try #require(throws: CocoaError.self) {
            try Storage(diskConfig: DiskConfig(name: name, directory: sandbox.root))
        }

        #expect(error.code == .fileWriteInvalidFileName)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.root.path) == ["bystander.txt"])
    }

    @Test("Other names work", arguments: ["Floppy", "with space", "a.b", ".hidden", "..dots", "…", "日本語"])
    func accepted(name: String) throws {
        let sandbox = try Sandbox()
        let storage = try Storage(diskConfig: DiskConfig(name: name, directory: sandbox.root))

        try storage.setObject(1, forKey: "key")

        #expect(try storage.object(ofType: Int.self, forKey: "key") == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.root.path) == [name])
    }
}
