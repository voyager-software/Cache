import Foundation

/// Convert to and from data
enum DataSerializer {
    // MARK: Internal

    /// Convert object to data
    ///
    /// - Parameter object: The object to convert
    /// - Returns: Data
    /// - Throws: Encoder error if any
    static func serialize(object: some Encodable) throws -> Data {
        try self.encoder.encode(object)
    }

    /// Convert data to object
    ///
    /// - Parameter data: The data to convert
    /// - Returns: The object
    /// - Throws: Decoder error if any
    static func deserialize<T: Decodable>(data: Data) throws -> T {
        try self.decoder.decode(T.self, from: data)
    }

    // MARK: Private

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
