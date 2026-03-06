import Foundation

public struct ImageWrapper: Codable, Sendable {
    // MARK: Lifecycle

    public init(image: Image) {
        self.image = image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: CodingKeys.image)
        guard let image = Image(data: data) else {
            throw StorageError.decodingFailed(context: "ImageWrapper: failed to create Image from data", underlyingError: nil)
        }

        self.image = image
    }

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
        case image
    }

    public let image: Image

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard let data = image.cache_toData() else {
            throw StorageError.encodingFailed(context: "ImageWrapper: failed to convert Image to data", underlyingError: nil)
        }

        try container.encode(data, forKey: CodingKeys.image)
    }
}
