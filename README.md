## Table of Contents

* [Description](#description)
* [Key features](#key-features)
* [Usage](#usage)
  * [Storage](#storage)
  * [Configuration](#configuration)
  * [APIs](#apis)
  * [Expiry date](#expiry-date)
* [What about images?](#what-about-images)
* [Installation](#installation)
* [Author](#author)
* [Contributing](#contributing)
* [License](#license)

## Description

**Cache** doesn't claim to be unique in this area, but it's not another monster
library that gives you a god's power. It does nothing but caching, but it does it well. It offers a good public API
with out-of-box implementations and great customization possibilities. `Cache` utilizes `Codable` to perform serialization.

## Key features

- [x] Works with `Codable` and `Sendable`. Anything conforming to both will be saved and loaded easily by `Storage`.
- [x] Disk, memory, or hybrid storage modes.
- [x] Many options via `DiskConfig` and `MemoryConfig`.
- [x] Support `expiry` and clean up of expired objects.
- [x] Thread safe. `Storage` is `Sendable` and can be accessed from any queue.
- [x] Store images via `ImageWrapper`.
- [x] iOS, tvOS, macOS, watchOS and visionOS support.

## Usage

### Storage

`Cache` is built based on [Chain-of-responsibility pattern](https://en.wikipedia.org/wiki/Chain-of-responsibility_pattern), in which there are many processing objects, each knows how to do 1 task and delegates to the next one. But that's just implementation detail. All you need to know is `Storage`, it saves and loads `Codable` objects.

`Storage` supports three modes: disk-only, memory-only, or hybrid (memory + disk). Memory storage is fast but volatile, while disk storage persists across application launches.

```swift
// Disk only
let diskConfig = DiskConfig(name: "Floppy")
let storage = try Storage(diskConfig: diskConfig)

// Hybrid (memory + disk)
let memoryConfig = MemoryConfig(expiry: .never, countLimit: 10)
let storage = try Storage(diskConfig: diskConfig, memoryConfig: memoryConfig)

// Memory only
let storage = Storage(memoryConfig: MemoryConfig(expiry: .never, countLimit: 50))
```

#### Codable types

`Storage` supports any objects that conform to [Codable](https://developer.apple.com/documentation/swift/codable) protocol. You can [make your own things conform to Codable](https://developer.apple.com/documentation/foundation/archives_and_serialization/encoding_and_decoding_custom_types) so that can be saved and loaded from `Storage`.

The supported types are

- Primitives like `Int`, `Float`, `String`, `Bool`, ...
- Array of primitives like `[Int]`, `[Float]`, `[Double]`, ...
- Set of primitives like `Set<String>`, `Set<Int>`, ...
- Simply dictionary like `[String: Int]`, `[String: String]`, ...
- `Date`
- `URL`
- `Data`

#### Error handling

Error handling is done via `try catch`. `Storage` throws errors in terms of `StorageError`.

```swift
public enum StorageError: Error {
  /// Object can not be found
  case notFound(key: String)
  /// Object is found, but casting to requested type failed
  case typeNotMatch(key: String)
  /// The file attributes are malformed
  case malformedFileAttributes(key: String)
  /// Can't perform Decode
  case decodingFailed(context: String, underlyingError: Error?)
  /// Can't perform Encode
  case encodingFailed(context: String, underlyingError: Error?)
}
```

There can be errors because of disk problem or type mismatch when loading from storage, so if want to handle errors, you need to do `try catch`

```swift
do {
  let storage = try Storage(diskConfig: diskConfig, memoryConfig: memoryConfig)
} catch {
  print(error)
}
```

### Configuration

Here is how you can play with many configuration options

```swift
let diskConfig = DiskConfig(
  // The name of disk storage, this will be used as folder name within directory
  name: "Floppy",
  // Expiry date that will be applied by default for every added object
  // if it's not overridden in the `setObject(forKey:expiry:)` method
  expiry: .date(Date().addingTimeInterval(2*3600)),
  // Maximum size of the disk cache storage (in bytes)
  maxSize: 10000,
  // Where to store the disk cache. If nil, it is placed in `cachesDirectory` directory.
  directory: try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, 
    appropriateFor: nil, create: true).appendingPathComponent("MyPreferences"),
  // Data protection is used to store files in an encrypted format on disk and to decrypt them on demand
  protectionType: .complete
)
```

```swift
let memoryConfig = MemoryConfig(
  // Expiry date that will be applied by default for every added object
  // if it's not overridden in the `setObject(forKey:expiry:)` method
  expiry: .date(Date().addingTimeInterval(2*60)),
  /// The maximum number of objects in memory the cache should hold. 0 means no limit.
  countLimit: 50
)
```

On iOS, tvOS we can also specify `protectionType` on `DiskConfig` to add a level of security to files stored on disk by your app in the app’s container. For more information, see [FileProtectionType](https://developer.apple.com/documentation/foundation/fileprotectiontype)

### APIs

`Storage` is thread safe and `Sendable` — you can access it from any queue or task. All functions are constrained by the `StorageAware` protocol.

```swift
// Save to storage
try? storage.setObject(10, forKey: "score")
try? storage.setObject("Oslo", forKey: "my favorite city", expiry: .never)
try? storage.setObject(["alert", "sounds", "badge"], forKey: "notifications")
try? storage.setObject(data, forKey: "a bunch of bytes")
try? storage.setObject(authorizeURL, forKey: "authorization URL")

// Load from storage
let score = try? storage.object(ofType: Int.self, forKey: "score")
let favoriteCharacter = try? storage.object(ofType: String.self, forKey: "my favorite city")

// Check if an object exists
let hasFavoriteCharacter = try? storage.existsObject(forKey: "my favorite city")

// Remove an object in storage
try? storage.removeObject(forKey: "my favorite city")

// Remove all objects
try? storage.removeAll()

// Remove expired objects
try? storage.removeExpiredObjects()
```

#### Entry

There is time you want to get object together with its expiry information and meta data. You can use `Entry`

```swift
let entry = try? storage.entry(ofType: String.self, forKey: "my favorite city")
print(entry?.object)
print(entry?.expiry)
print(entry?.meta)
```

`meta` may contain file information if the object was fetched from disk storage.

#### Custom types

Types stored in `Storage` must conform to both `Codable` and `Sendable`. It does not work for `[String: Any]` as `Any` conforms to neither. Convert JSON responses to strongly typed objects before saving.

```swift
struct User: Codable, Sendable {
  let firstName: String
  let lastName: String
}

let user = User(firstName: "John", lastName: "Snow")
try? storage.setObject(user, forKey: "character")
```

### Expiry date

By default, all saved objects have the same expiry as the expiry you specify in `DiskConfig` or `MemoryConfig`. You can overwrite this for a specific object by specifying `expiry` for `setObject`

```swift
// Default expiry date from configuration will be applied to the item
try? storage.setObject("This is a string", forKey: "string")

// A given expiry date will be applied to the item
try? storage.setObject(
  "This is a string",
  forKey: "string",
  expiry: .date(Date().addingTimeInterval(2 * 3600))
)

// Clear expired objects
try? storage.removeExpiredObjects()
```

## What about images?

As you may know, `NSImage` and `UIImage` don't conform to `Codable` by default. To make it play well with `Codable`, we introduce `ImageWrapper`, so you can save and load images like

```swift
let wrapper = ImageWrapper(image: starIconImage)
try? storage.setObject(wrapper, forKey: "star")

let icon = try? storage.object(ofType: ImageWrapper.self, forKey: "star").image
```

If you want to load image into `UIImageView` or `NSImageView`, then we also have a nice gift for you. It's called [Imaginary](https://github.com/hyperoslo/Imaginary) and uses `Cache` under the hood to make you life easier when it comes to working with remote images.

## Authors

- Original idea: [Hyper](http://hyper.no) made this with ❤️
- Reworked, simplified and modernized: Gabor S

## License

**Cache** is available under the MIT license. 



Bug fixes
• Fixed LRU eviction sorting (was evicting newest instead of oldest)
• Fixed Expiry​.never using hardcoded 68-year date → Date​.distant​Future
• Fixed object(of​Type:) returning expired entries → now throws not​Found
• Fixed Sync​Storage forced unwrap crash pattern
• Fixed file​Manager​.create​File ignoring failure → now throws on false

Modernization
• Adopted async/await, raised platform minimums to iOS 16+/macOS 13+
• Replaced 280-line hand-rolled MD5 with CryptoKit Insecure​.​MD5
• Replaced NSString(string:) allocations with free as ​NSString bridging

Thread safety
• Added OSAllocated​Unfair​Lock to Memory​Storage, Disk​Storage, Hybrid​Storage
• Made entire storage chain genuinely Sendable (eliminated all @unchecked ​Sendable on storage types)
• Made Memory​Capsule final, private, @unchecked ​Sendable with any ​Sendable instead of Any

Removed dead code/redundant layers
• Deleted Sync​Storage, Async​Storage, Async​Storage​Aware, Result​.swift, Expiration​Mode​.swift, JSONDecoder​+​Extensions​.swift
• Removed unused total​Size() and remove​Object​If​Expired() from DiskStorage
• Removed deprecated Memory​Config initializer with total​Cost​Limit

API improvements
• Enriched Storage​Error with associated values (key, context, underlyingError)
• Added Storage​.init(memory​Config:) for memory-only caching
• Made Storage​Aware constraints consistently Codable & ​Sendable
• Made JSONDictionary​Wrapper Sendable
• Changed Data​Serializer from class to enum with static encoder/decoder

Code quality
• Replaced force casts with conditional casts in DiskStorage
• Tightened access control (private over fileprivate, consolidated private extensions)
• Renamed MD5​.​MD5() → MD5​.hash(), fixed parameter shadowing (remaining​Size)
• Made Storage​Aware internal, removed public from Type​Wrapper​Storage methods
• Fixed stale comment in NSImage​+​Extensions

README
• Updated to reflect all changes: removed async/Alamofire/SwiftHash sections, updated StorageError/MemoryConfig examples, documented three storage modes, fixed typos
