import Foundation

/**
 Helper enum to set the expiration date
 */
public enum Expiry: Sendable {
    /// Object will be expired in the nearest future
    case never
    /// Object will be expired in the specified amount of seconds
    case seconds(TimeInterval)
    /// Object will be expired on the specified date
    case date(Date)

    // MARK: Public

    /// Returns the appropriate date object
    public var date: Date {
        switch self {
        case .never:
            Date.distantFuture
        case let .seconds(seconds):
            Date().addingTimeInterval(seconds)
        case let .date(date):
            date
        }
    }

    /// Checks if cached object is expired according to expiration date
    public var isExpired: Bool {
        self.date.inThePast
    }
}
