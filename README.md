<p align="center"><img src="Assets/logo.png" width="128" height="128" alt="Cache logo"></p>

<h1 align="center">Cache</h1>

Stores `Codable & Sendable` values on disk, in memory, or both, with expiry. Thread safe.

Requires iOS 16, macOS 13, tvOS 16, watchOS 9 or visionOS 1.

## Installation

```swift
.package(url: "https://github.com/voyager-software/Cache.git", from: "5.0.0")
```

## Usage

```swift
// Disk
let storage = try Storage(diskConfig: DiskConfig(name: "Floppy"))

// Disk, with objects also kept in memory
let storage = try Storage(diskConfig: DiskConfig(name: "Floppy"), memoryConfig: MemoryConfig(countLimit: 50))

// Memory
let storage = Storage(memoryConfig: MemoryConfig(countLimit: 50))
```

```swift
try storage.setObject(user, forKey: "user")
try storage.setObject(user, forKey: "user", expiry: .seconds(3600))

let user = try storage.object(ofType: User.self, forKey: "user")
let entry = try storage.entry(ofType: User.self, forKey: "user") // entry.object, entry.expiry
let exists = try storage.existsObject(forKey: "user")

try storage.removeObject(forKey: "user")
try storage.removeExpiredObjects()
try storage.removeAll()

let bytes = try storage.diskSize()
```

## Configuration

```swift
DiskConfig(
    name: "Floppy",               // Folder name
    expiry: .never,               // Default expiry
    directory: nil,               // Where the folder goes. nil means the Caches directory
    protectionType: .complete     // iOS and tvOS only
)

MemoryConfig(
    expiry: .never,               // Default expiry
    countLimit: 0                 // Maximum number of objects. 0 means no limit
)
```

The folder must be used only by the storage: `removeExpiredObjects()` deletes every file in it that isn't one of its objects, whatever its age and hidden files included.

## Expiry

`.never`, `.seconds(TimeInterval)` or `.date(Date)`. It's set by the config, or per object in `setObject`.

An expired object counts as missing, but its file stays on disk until `removeExpiredObjects()`.

## Errors

| Error | When |
|---|---|
| `notFound` | There's no object for the key, or it has expired |
| `typeNotMatch` | The object in memory is a different type |
| `decodingFailed` | The data on disk can't be decoded as the requested type |
| `encodingFailed` | The object can't be encoded, or the file can't be written |
| `malformedFileAttributes` | The file's expiry can't be read |

Other file system errors are passed through unchanged, for example reading a protected file while the device is locked.

## File protection

- `protectionType` applies to files written from now on. A file that's already there keeps its protection until it's overwritten.
- With `.complete`, reading from disk and writing throw while the device is locked. Opening a `Storage` still works, and `existsObject(forKey:)` can return `true` for an object that can't be read at that moment.
- It only covers files on disk. An object already in memory stays readable while the device is locked, so use disk-only storage for sensitive data.

## Authors

- Original idea: [Hyper](http://hyper.no)
- Reworked, simplified and modernized: Gabor S

## License

MIT
