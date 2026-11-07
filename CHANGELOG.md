# Changelog

## 5.0.0

Removed
- `ImageWrapper`, the `Image` typealias, `JSONArrayWrapper`, `JSONDictionaryWrapper`, `JSONArray` and `JSONDictionary`. The package no longer depends on UIKit or AppKit.
- `DiskConfig.maxSize`, which was only enforced by `removeExpiredObjects()`.
- `Entry.meta`, which was always empty.
- The public `StorageAware` protocol. Use `Storage`.

Behaviour changes
- `entry(ofType:forKey:)` treats an expired object as missing and throws `StorageError.notFound`, like `object(ofType:forKey:)`. Disk reads check the expiry first, so an expired object isn't read or decoded.
- Objects are stored without a wrapper, and `Data` is stored as it is instead of base64 in JSON. That takes about a quarter less disk space for `Data`.

Added
- `Storage.diskSize()`.

Upgrading
- Existing caches start empty. Files from 4.x are never read, and `removeExpiredObjects()` removes them. They stay on disk until then, or until `removeAll()`.
- `removeExpiredObjects()` deletes every file in the folder that isn't one of the storage's objects, hidden files included, so keep nothing else in it.
- Replace `entry(...)` followed by an `isExpired` check with `object(...)`, or just remove the check.
- Remove `maxSize:` from `DiskConfig(...)`.

## 4.10.1

Bug fixes
- `removeExpiredObjects()` no longer stops at the first file it can't read or remove. It carries on, then throws the first failure at the end. A file that vanished during the purge isn't a failure.
- Hybrid storage writes to disk before memory, so a failed write no longer leaves memory holding a value that wasn't saved.

Other
- Documented how `protectionType` treats existing files, and how `.complete` behaves while the device is locked.
- Added CI.

## 4.10.0

Bug fixes
- Writing brings back a cache folder that was deleted, for example when the system purges Caches. `removeAll()` no longer fails in that case either, and brings the folder back too.
- `removeAll()` keeps the configured `protectionType` when it recreates the folder.
- Fixed the privacy manifest's file timestamp reason: `C617.1` instead of `DDA9.1`.
- Fixed the build for watchOS, where `Image` wasn't defined.
- `removeExpiredObjects()` forgets the memory keys of objects that `NSCache` has evicted, which used to pile up.

Behaviour changes
- A miss on disk throws `StorageError.notFound`, and stored data that can't be decoded throws `StorageError.decodingFailed`. Both used to throw the system's error.
- Encoding failures throw `StorageError.encodingFailed`, and failed writes now include the cause in `underlyingError`.
- `removeObject(forKey:)` does nothing for a missing key on disk and hybrid storage, like it does in memory. It used to throw.

Other
- Added tests.
- Corrected comments and the README. Moved the changelog out of the README.

## Rework, up to 4.9.0

Bug fixes
- Fixed eviction sorting (was evicting newest instead of oldest)
- Fixed `Expiry.never` using hardcoded 68-year date → `Date.distantFuture`
- Fixed `object(ofType:)` returning expired entries → now throws `notFound`
- Fixed `SyncStorage` forced unwrap crash pattern
- Fixed `fileManager.createFile` ignoring failure → now throws on false

Modernization
- Adopted async/await, raised platform minimums to iOS 16+/macOS 13+
- Replaced 280-line hand-rolled MD5 with CryptoKit `Insecure.MD5`
- Replaced `NSString(string:)` allocations with free `as NSString` bridging

Thread safety
- Added `OSAllocatedUnfairLock` to `MemoryStorage`, `DiskStorage`, `HybridStorage`
- Made entire storage chain genuinely `Sendable` (eliminated all `@unchecked Sendable` on storage types)
- Made `MemoryCapsule` final, private, `@unchecked Sendable` with `any Sendable` instead of `Any`

Removed dead code/redundant layers
- Deleted `SyncStorage`, `AsyncStorage`, `AsyncStorageAware`, `Result.swift`, `ExpirationMode.swift`, `JSONDecoder+Extensions.swift`
- Removed unused `totalSize()` and `removeObjectIfExpired()` from `DiskStorage`
- Removed deprecated `MemoryConfig` initializer with `totalCostLimit`

API improvements
- Enriched `StorageError` with associated values (key, context, underlyingError)
- Added `Storage.init(memoryConfig:)` for memory-only caching
- Made `StorageAware` constraints consistently `Codable & Sendable`
- Made `JSONDictionaryWrapper` `Sendable`
- Changed `DataSerializer` from class to enum with static encoder/decoder

Code quality
- Replaced force casts with conditional casts in `DiskStorage`
- Tightened access control (private over fileprivate, consolidated private extensions)
- Renamed `MD5.MD5()` → `MD5.hash()`, fixed parameter shadowing (`remainingSize`)
- Removed public from `TypeWrapperStorage` methods
- Fixed stale comment in `NSImage+Extensions`

README
- Updated to reflect all changes: removed async/Alamofire/SwiftHash sections, updated `StorageError`/`MemoryConfig` examples, documented three storage modes, fixed typos
