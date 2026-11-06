import Foundation
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

    func folder(named name: String = "cache") -> URL {
        self.root.appendingPathComponent(name, isDirectory: true)
    }

    func storage(_ mode: Mode, name: String = "cache", maxSize: UInt = 0, countLimit: UInt = 0) throws -> Storage {
        let disk = DiskConfig(name: name, maxSize: maxSize, directory: self.root)
        let memory = MemoryConfig(countLimit: countLimit)
        return switch mode {
        case .disk:
            try Storage(diskConfig: disk)
        case .hybrid:
            try Storage(diskConfig: disk, memoryConfig: memory)
        case .memory:
            Storage(memoryConfig: memory)
        }
    }

    func files(named name: String = "cache") throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: self.folder(named: name).path)
    }
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
