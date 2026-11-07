# Changelog

## 5.0.1

Bug fixes
- With both disk and memory, an object could stay readable after its file expired, because the copy in memory used `MemoryConfig.expiry`. An object now has one expiry, and `entry(ofType:forKey:)` reports the same one from memory and from disk.
- A `DiskConfig` name that isn't a single folder is refused, because purging or `removeAll()` could delete files outside the cache. With an empty name, they emptied `directory` itself. `Storage` now throws `CocoaError(.fileWriteInvalidFileName)`.
- A `DiskConfig` name with a control character such as NUL is refused too, and so is a `directory` with a NUL in it. File system calls stop reading a path at a NUL, so purging could act on files far outside the cache.
- `removeExpiredObjects()` and `removeAll()` only delete files named like the storage's objects, directly in its folder. Purging used to delete every other file in the folder and in its subfolders, and `removeAll()` deleted the whole folder, so a wrong path could cost files that had nothing to do with the cache.
- An object in memory no longer waits for disk access or encoding of another object.
- An object's relative expiry, like `.seconds(10)`, starts once it's being saved. Waiting for another write or a disk read used to use it up, so a short-lived object could be saved already expired.
- Encoding and decoding no longer hold any lock, so a slow `Codable` type doesn't hold up other objects, and its code can use the storage it's being saved in.

Behaviour changes
- `MemoryConfig.expiry` is now only used by memory-only storage. With a disk, objects use the expiry from `DiskConfig`.
- Files in the cache folder that aren't the storage's, hidden ones included, are no longer deleted by `removeExpiredObjects()` or `removeAll()`. They still count toward `diskSize()`.
- A `DiskConfig` name with a `/`, like `"Images/Thumbnails"`, used to create nested folders and now throws. Pass the parent folder as `directory` instead. Use the same full path to keep what's already cached there.

Other
- Documented that objects should be read with the type they were written as. On disk, `Data` returns a file's bytes without checking what was written, so an object written as `Data?` comes back as JSON.
- Added tests that compare all kinds of storage, cover the config's default expiry and use storage from many threads. CI also runs the tests with Thread Sanitizer.

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
