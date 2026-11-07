import Foundation

public struct DiskConfig: Sendable {
    /// The name of disk storage, this will be used as folder name within directory.
    /// It must be a single folder name: `Storage` refuses an empty name, `.`, `..`, and anything with
    /// a `/` or a control character such as NUL. The storage only ever deletes files named like its
    /// objects, directly in this folder, so anything else kept there is left alone.
    public let name: String
    /// Expiry date that will be applied by default for every added object
    /// if it's not overridden in the `setObject(_:forKey:expiry:)` method
    public let expiry: Expiry
    /// A folder to store the disk cache contents. Defaults to the Caches directory if nil
    public let directory: URL?
    #if os(iOS) || os(tvOS)
    /// Data protection is used to store files in an encrypted format on disk and to decrypt them on demand.
    /// Support only on iOS and tvOS. Applies to files written from now on: a file that's already
    /// there keeps its protection until it's overwritten. Only covers files on disk: with a memory
    /// layer, an object already in memory stays readable while the device is locked.
    public let protectionType: FileProtectionType?

    public init(name: String, expiry: Expiry = .never,
                directory: URL? = nil,
                protectionType: FileProtectionType? = nil)
    {
        self.name = name
        self.expiry = expiry
        self.directory = directory
        self.protectionType = protectionType
    }
    #else
    public init(name: String, expiry: Expiry = .never,
                directory: URL? = nil)
    {
        self.name = name
        self.expiry = expiry
        self.directory = directory
    }
    #endif
}
