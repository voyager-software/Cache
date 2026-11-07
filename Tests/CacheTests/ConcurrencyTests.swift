import Foundation
import os
import Testing
@testable import Cache

@Suite("Concurrency")
struct ConcurrencyTests {
    // MARK: Using it from many threads

    /// Mostly here for Thread Sanitizer, which CI runs it under. Values carry their key, to catch mix-ups.
    @Test("Many threads can use a storage at once", arguments: Sandbox.Mode.allCases)
    func manyThreads(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        // A small limit, so that NSCache evicts while this runs
        let storage = try sandbox.storage(mode, countLimit: 5)
        let failures = OSAllocatedUnfairLock(initialState: [String]())

        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            for iteration in 0 ..< 300 {
                let keyNumber = (iteration + thread) % 10
                let key = "key\(keyNumber)"
                do {
                    try storage.setObject(iteration * 10 + keyNumber, forKey: key,
                                          expiry: iteration % 3 == 0 ? .seconds(-1) : .seconds(60))
                    _ = try storage.existsObject(forKey: key)
                    do {
                        let value = try storage.object(ofType: Int.self, forKey: key)
                        if value % 10 != keyNumber {
                            failures.withLock { $0.append("\(key) held \(value)") }
                        }
                    }
                    catch StorageError.notFound {
                        // It expired, or another thread removed it
                    }
                    if iteration % 20 == 0 { try storage.removeObject(forKey: key) }
                    if iteration % 50 == 0 {
                        try storage.removeExpiredObjects()
                        _ = try storage.diskSize()
                    }
                    if iteration % 120 == 0 { try storage.removeAll() }
                }
                catch {
                    failures.withLock { $0.append("\(error)") }
                }
            }
        }

        #expect(failures.withLock { $0 } == [])
    }

    // MARK: Not waiting for each other

    /// Runs the code on another thread while `write` is stuck at the gate.
    private func whileHeldUp(at gate: Gate, write: @escaping @Sendable () -> Void, _ code: () throws -> Void) throws {
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            write()
            finished.signal()
        }
        gate.waitUntilEntered()
        defer {
            gate.release()
            finished.wait()
            #expect(!gate.timedOut, "The code had to wait for the write to finish")
        }
        try code()
    }

    @Test("A slow encode doesn't hold up other objects", arguments: [Sandbox.Mode.disk, .hybrid])
    func slowEncode(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        try storage.setObject(1, forKey: "existing")
        let gate = Gate()

        try whileHeldUp(at: gate, write: { try? storage.setObject(HeldUpWhileEncoding(gate: gate), forKey: "slow") }) {
            #expect(try storage.object(ofType: Int.self, forKey: "existing") == 1)
            try storage.setObject(2, forKey: "other")
            #expect(try storage.object(ofType: Int.self, forKey: "other") == 2)
            try storage.removeObject(forKey: "other")
        }
    }

    @Test("A slow disk doesn't hold up an object that's in memory")
    func slowDisk() throws {
        let sandbox = try Sandbox()
        let fileManager = HookedFileManager()
        let disk = try DiskStorage(config: DiskConfig(name: "cache", directory: sandbox.root), fileManager: fileManager)
        let storage = HybridStorage(memoryStorage: MemoryStorage(config: MemoryConfig()), diskStorage: disk)
        try storage.setObject(1, forKey: "inMemory", expiry: nil)
        let gate = Gate()
        fileManager.beforeSettingAttributes = { gate.enter() }

        try whileHeldUp(at: gate, write: { try? storage.setObject(2, forKey: "slow", expiry: nil) }) {
            let value = try storage.object(ofType: Int.self, forKey: "inMemory")
            let exists = try storage.existsObject(forKey: "inMemory")
            #expect(value == 1)
            #expect(exists)
        }
    }

    // MARK: Using the storage from Codable code

    @Test("A type's Codable code can use the storage it's being saved in", arguments: [Sandbox.Mode.disk, .hybrid])
    func codableCodeUsesStorage(mode: Sandbox.Mode) throws {
        let sandbox = try Sandbox()
        let storage = try sandbox.storage(mode)
        // A new instance, because hybrid storage would otherwise answer from memory without decoding
        let reader = try sandbox.storage(mode)
        let writerRan = OSAllocatedUnfairLock(initialState: false)
        let readerRan = OSAllocatedUnfairLock(initialState: false)

        try RunsCodeInCodable.$code.withValue({
            try? storage.setObject(1, forKey: "other")
            writerRan.withLock { $0 = true }
        }) {
            try storage.setObject(RunsCodeInCodable(), forKey: "key")
        }
        _ = try RunsCodeInCodable.$code.withValue({
            _ = try? reader.object(ofType: Int.self, forKey: "other")
            readerRan.withLock { $0 = true }
        }) {
            try reader.object(ofType: RunsCodeInCodable.self, forKey: "key")
        }

        #expect(writerRan.withLock { $0 })
        #expect(readerRan.withLock { $0 })
    }

    // MARK: Filling memory from disk

    @Test("An object removed during decoding doesn't come back into memory")
    func removedWhileDecoding() throws {
        let sandbox = try Sandbox()
        try sandbox.storage(.hybrid).setObject(RunsCodeInCodable(), forKey: "key")
        let storage = try sandbox.storage(.hybrid)

        _ = try RunsCodeInCodable.$code.withValue({
            try? storage.removeObject(forKey: "key")
        }) {
            try storage.object(ofType: RunsCodeInCodable.self, forKey: "key")
        }

        #expect(try storage.existsObject(forKey: "key") == false)
    }

    @Test("An object from disk is kept in memory after reading it")
    func readingFillsMemory() throws {
        let sandbox = try Sandbox()
        try sandbox.storage(.hybrid).setObject(1, forKey: "key")
        let storage = try sandbox.storage(.hybrid)

        #expect(try storage.object(ofType: Int.self, forKey: "key") == 1)
        try FileManager.default.removeItem(at: sandbox.folder())

        #expect(try storage.object(ofType: Int.self, forKey: "key") == 1)
    }
}
