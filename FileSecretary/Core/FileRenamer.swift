import Foundation

// MARK: - RenameItem

struct RenameItem: Identifiable {
    var id = UUID()
    var originalURL: URL
    var customName: String?   // nil → use original base name
    var isSelected: Bool = true

    var baseName: String { customName ?? originalURL.deletingPathExtension().lastPathComponent }
    var ext: String { originalURL.pathExtension }
    var displayName: String { originalURL.lastPathComponent }
}

// MARK: - FileRenamer

class FileRenamer {

    struct RenameResult {
        var renamed: [(from: URL, to: URL)] = []
        var failed: [URL] = []
    }

    func apply(items: [RenameItem],
               digits: Int,
               startNumber: Int,
               unifiedBaseName: String,
               unifyMode: Int = 0,
               useNumbering: Bool = true) -> RenameResult {
        var result = RenameResult()
        let trimmedBase = unifiedBaseName.trimmingCharacters(in: .whitespaces)

        for (i, item) in items.enumerated() {
            let base: String
            if !trimmedBase.isEmpty {
                if unifyMode == 0 {
                    base = trimmedBase
                } else {
                    let originalBase = item.originalURL.deletingPathExtension().lastPathComponent
                    base = "\(trimmedBase)(\(originalBase))"
                }
            } else {
                base = item.baseName
            }

            let ext = item.ext.isEmpty ? "" : ".\(item.ext)"
            let newName: String
            if useNumbering {
                let numStr = String(format: "%0\(digits)d", startNumber + i)
                newName = "\(numStr)_\(base)\(ext)"
            } else {
                newName = "\(base)\(ext)"
            }

            let destURL = item.originalURL
                .deletingLastPathComponent()
                .appendingPathComponent(newName)

            guard destURL != item.originalURL else { continue }

            do {
                try FileManager.default.moveItem(at: item.originalURL, to: destURL)
                result.renamed.append((from: item.originalURL, to: destURL))
            } catch {
                result.failed.append(item.originalURL)
            }
        }
        return result
    }
}
