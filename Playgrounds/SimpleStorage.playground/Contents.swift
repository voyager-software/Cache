//: Playground - noun: a place where people can play
import PlaygroundSupport
import UIKit
import Cache

struct User: Codable {
    let id: Int
    let firstName: String
    let lastName: String

    var name: String {
        "\(self.firstName) \(self.lastName)"
    }
}

let diskConfig = DiskConfig(name: "UserCache")
let memoryConfig = MemoryConfig(expiry: .never, countLimit: 10)

let storage = try! Storage(diskConfig: diskConfig, memoryConfig: memoryConfig)

let user = User(id: 1, firstName: "John", lastName: "Snow")
let key = "\(user.id)"

// Add objects to the cache
try storage.setObject(user, forKey: key)

// Fetch object from the cache

do {
    let user = try storage.object(ofType: User.self, forKey: key)
    print(user.name)
}
catch {
    print(error)
}

// Remove object from the cache
try storage.removeObject(forKey: key)

// Try to fetch removed object from the cache

do {
    let user = try storage.object(ofType: User.self, forKey: key)
    print(user.name)
}
catch {
    print(error)
}

// Clear cache
try storage.removeAll()

PlaygroundPage.current.needsIndefiniteExecution = true
