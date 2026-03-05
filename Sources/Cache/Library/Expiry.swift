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

  /// Returns the appropriate date object
  public var date: Date {
    switch self {
    case .never:
      return Date.distantFuture
    case .seconds(let seconds):
      return Date().addingTimeInterval(seconds)
    case .date(let date):
      return date
    }
  }

  /// Checks if cached object is expired according to expiration date
  public var isExpired: Bool {
    return date.inThePast
  }
}
