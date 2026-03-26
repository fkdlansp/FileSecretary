import Foundation

struct UndoEntry {
    let moves: [(from: URL, to: URL)]
}

class UndoHistory {
    private var stack: [UndoEntry] = []

    var count: Int { stack.count }

    func push(_ result: OrganizeResult) {
        guard !result.moved.isEmpty else { return }
        stack.append(UndoEntry(moves: result.moved))
    }

    /// Undo the last organize operation, moving files back to their original locations.
    /// Returns the number of files successfully restored.
    @discardableResult
    func undo() -> Int {
        guard let entry = stack.popLast() else { return 0 }
        let fm = FileManager.default
        var restored = 0
        for move in entry.moves.reversed() {
            // move.to = current location, move.from = original location
            guard fm.fileExists(atPath: move.to.path) else { continue }
            guard !fm.fileExists(atPath: move.from.path) else { continue }
            let destDir = move.from.deletingLastPathComponent()
            do {
                if !fm.fileExists(atPath: destDir.path) {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                }
                try fm.moveItem(at: move.to, to: move.from)
                restored += 1
            } catch {
                // Skip this file, continue with others
            }
        }
        return restored
    }
}
