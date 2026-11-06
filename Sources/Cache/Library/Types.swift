#if canImport(UIKit)
import UIKit

public typealias Image = UIImage
#elseif os(macOS)
import AppKit

public typealias Image = NSImage
#endif
