import Foundation
import CryptoKit

enum MD5 {
    /// Returns the MD5 hex digest (uppercase) of the given string.
    static func hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}
