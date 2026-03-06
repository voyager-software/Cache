import Foundation

public typealias JSONDictionary = [String: any Sendable]

public struct JSONDictionaryWrapper: Codable, Sendable {
    // MARK: Lifecycle

    public init(jsonDictionary: JSONDictionary) {
        self.jsonDictionary = jsonDictionary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: CodingKeys.jsonDictionary)
        let object = try JSONSerialization.jsonObject(
            with: data,
            options: []
        )

        guard let jsonDictionary = object as? JSONDictionary else {
            throw StorageError.decodingFailed(context: "JSONDictionaryWrapper: JSON object is not a dictionary", underlyingError: nil)
        }

        self.jsonDictionary = jsonDictionary
    }

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
        case jsonDictionary
    }

    public let jsonDictionary: JSONDictionary

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let data = try JSONSerialization.data(
            withJSONObject: self.jsonDictionary,
            options: []
        )

        try container.encode(data, forKey: CodingKeys.jsonDictionary)
    }
}
