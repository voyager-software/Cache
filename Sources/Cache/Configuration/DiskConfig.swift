import Foundation

public struct DiskConfig: Sendable {
    /// The name of disk storage, this will be used as folder name within directory
    public let name: String
    /// Expiry date that will be applied by default for every added object
    /// if it's not overridden in the `setObject(_:forKey:expiry:)` method
    public let expiry: Expiry
    /// Maximum size of the disk cache storage (in bytes). 0 means no limit.
    /// Only enforced by `removeExpiredObjects()`, which then removes the objects closest to
    /// expiring until the storage is under half of this size.
    public let maxSize: UInt
    /// A folder to store the disk cache contents. Defaults to the Caches directory if nil
    public let directory: URL?
    #if os(iOS) || os(tvOS)
    /// Data protection is used to store files in an encrypted format on disk and to decrypt them on demand.
    /// Support only on iOS and tvOS. Applies to files written from now on: a file that's already
    /// there keeps its protection until it's overwritten. Only covers files on disk: with a memory
    /// layer, an object already in memory stays readable while the device is locked.
    public let protectionType: FileProtectionType?

    public init(name: String, expiry: Expiry = .never,
                maxSize: UInt = 0, directory: URL? = nil,
                protectionType: FileProtectionType? = nil)
    {
        self.name = name
        self.expiry = expiry
        self.maxSize = maxSize
        self.directory = directory
        self.protectionType = protectionType
    }
    #else
    public init(name: String, expiry: Expiry = .never,
                maxSize: UInt = 0, directory: URL? = nil)
    {
        self.name = name
        self.expiry = expiry
        self.maxSize = maxSize
        self.directory = directory
    }
    #endif
}
