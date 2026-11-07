import Foundation
// Builds URLs and prints them. No file system calls.
let root = FileManager.default.temporaryDirectory.appendingPathComponent("CacheTests-1", isDirectory: true)
print("root:", root.absoluteString, root.path.debugDescription)
for part in ["\u{0}", "\u{0}x", "a\u{0}b"] {
    let u = root.appendingPathComponent(part, isDirectory: true)
    let c = u.appendingPathComponent("cache", isDirectory: true)
    let fs = c.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } ?? "nil" }
    print(part.debugDescription, "| abs:", u.absoluteString, "| path:", u.path.debugDescription,
          "| isFile:", u.isFileURL, "| child path:", c.path.debugDescription, "| child fsRep:", fs)
}
