import Foundation

enum DuplicateMode: String, Codable {
    case addNumber
    case overwrite
    case skip
}

struct DuplicateResolver {

    /// Returns the final destination URL to use, or nil if the file should be skipped.
    func resolve(source: URL, destination: URL, mode: DuplicateMode) throws -> URL? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: destination.path) else {
            return destination
        }

        switch mode {
        case .skip:
            return nil
        case .overwrite:
            try fm.removeItem(at: destination)
            return destination
        case .addNumber:
            return numberedURL(for: destination, fm: fm)
        }
    }

    // MARK: Private

    private func numberedURL(for url: URL, fm: FileManager) -> URL {
        let dir  = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext  = url.pathExtension
        var n = 2
        while true {
            let candidate: URL
            if ext.isEmpty {
                candidate = dir.appendingPathComponent("\(base) \(n)")
            } else {
                candidate = dir.appendingPathComponent("\(base) \(n).\(ext)")
            }
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
