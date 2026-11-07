//: Playground - noun: a place where people can play
import PlaygroundSupport
import UIKit
import Cache

enum Helper {
    static func data(length: Int) -> Data {
        var buffer = [UInt8](repeating: 0, count: length)
        return Data(bytes: &buffer, count: length)
    }
}

// MARK: - Storage

let diskConfig = DiskConfig(name: "Mix")

let storage = try! Storage(diskConfig: diskConfig)

let string = "This is a string"
let data = Helper.data(length: 64)
let date = Date(timeInterval: 100_000, since: Date())

// Add objects to the cache
try storage.setObject(string, forKey: "string")
try storage.setObject(data, forKey: "data")
try storage.setObject(date, forKey: "date")
///
//// Get objects from the cache
let cachedString = try? storage.object(ofType: String.self, forKey: "string")
print(cachedString ?? "")

if let data = try? storage.object(ofType: Data.self, forKey: "data") {
    print(data)
}

if let date = try? storage.object(ofType: Date.self, forKey: "date") {
    print(date)
}

// Clean the cache
try storage.removeAll()

PlaygroundPage.current.needsIndefiniteExecution = true
