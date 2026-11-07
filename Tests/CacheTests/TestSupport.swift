import Foundation
import os
@testable import Cache

/// A folder that lasts as long as a test, with the three kinds of storage inside it.
final class Sandbox {
    // MARK: Lifecycle

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Internal

    enum Mode: String, CaseIterable {
        case disk
        case hybrid
        case memory
    }

    let root: URL

    func folder() -> URL {
        self.root.appendingPathComponent("cache", isDirectory: true)
    }

    /// - Parameter expiry: The default expiry, in the config of whichever kinds of storage are used
    func storage(_ mode: Mode, expiry: Expiry = .never, countLimit: UInt = 0) throws -> Storage {
        let disk = DiskConfig(name: "cache", expiry: expiry, directory: self.root)
        let memory = MemoryConfig(expiry: expiry, countLimit: countLimit)
        return switch mode {
        case .disk:
            try Storage(diskConfig: disk)
        case .hybrid:
            try Storage(diskConfig: disk, memoryConfig: memory)
        case .memory:
            Storage(memoryConfig: memory)
        }
    }

    func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: self.folder().path)
    }
}

/// What a key's file is called on disk.
func fileName(for key: String) -> String {
    "\(MD5.hash(key)).\(DiskStorage.fileExtension)"
}

struct Person: Codable, Sendable, Equatable {
    let name: String
}

/// Always fails to encode, with a plain error.
struct Unencodable: Codable, Sendable {
    struct Failure: Error {}

    func encode(to _: Encoder) throws {
        throw Failure()
    }
}

/// Always fails to encode, with an error that already says what went wrong.
struct UnencodableWithStorageError: Codable, Sendable {
    func encode(to _: Encoder) throws {
        throw StorageError.encodingFailed(context: "inner", underlyingError: nil)
    }
}

/// Runs hooks during file operations, which can fail them, delete the file first, or hold them up.
final class HookedFileManager: FileManager, @unchecked Sendable {
    var beforeRemoving: (String) throws -> Void = { _ in }
    var beforeSettingAttributes: () -> Void = {}

    override func removeItem(atPath path: String) throws {
        try self.beforeRemoving(path)
        try super.removeItem(atPath: path)
    }

    override func removeItem(at url: URL) throws {
        try self.beforeRemoving(url.path)
        try super.removeItem(at: url)
    }

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        self.beforeSettingAttributes()
        try super.setAttributes(attributes, ofItemAtPath: path)
    }
}

/// Holds one thread up until another has done something. Gives up after a while and remembers
/// that it did, so that a test fails if the other thread was stuck behind it, rather than hanging.
final class Gate: Sendable {
    // MARK: Internal

    var timedOut: Bool {
        self.didTimeOut.withLock { $0 }
    }

    /// Called by the thread being held up.
    func enter() {
        self.entered.signal()
        if self.released.wait(timeout: .now() + 5) == .timedOut {
            self.didTimeOut.withLock { $0 = true }
        }
    }

    func waitUntilEntered() {
        self.entered.wait()
    }

    func release() {
        self.released.signal()
    }

    // MARK: Private

    private let entered = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private let didTimeOut = OSAllocatedUnfairLock(initialState: false)
}

/// Waits at a gate while it's being encoded.
struct HeldUpWhileEncoding: Codable, Sendable {
    // MARK: Lifecycle

    init(gate: Gate) {
        self.gate = gate
    }

    init(from _: Decoder) throws {
        self.gate = nil
    }

    // MARK: Internal

    func encode(to encoder: Encoder) throws {
        self.gate?.enter()
        var container = encoder.singleValueContainer()
        try container.encode(1)
    }

    // MARK: Private

    private let gate: Gate?
}

/// Runs some code of the test's while it's being encoded or decoded, like a type whose `Codable`
/// code uses the storage it's being saved in.
struct RunsCodeInCodable: Codable, Sendable {
    // MARK: Lifecycle

    init() {}

    init(from _: Decoder) throws {
        Self.code?()
    }

    // MARK: Internal

    @TaskLocal static var code: (@Sendable () -> Void)?

    func encode(to encoder: Encoder) throws {
        Self.code?()
        var container = encoder.singleValueContainer()
        try container.encode(1)
    }
}
