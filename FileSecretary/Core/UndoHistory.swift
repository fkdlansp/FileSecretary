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
    /// Also removes empty folders that were created during the organize.
    /// Returns (restored moves, skipped URLs).
    @discardableResult
    func undo() -> (restored: [(from: URL, to: URL)], skipped: [URL]) {
        guard let entry = stack.popLast() else { return ([], []) }
        let fm = FileManager.default
        var restored: [(from: URL, to: URL)] = []
        var skipped:  [URL] = []

        // 정리 시 생성된 폴더 목록 수집 (중복 제거)
        var createdFolders = Set(entry.moves.map { $0.to.deletingLastPathComponent().path })

        for move in entry.moves.reversed() {
            // move.to = current location, move.from = original location
            guard fm.fileExists(atPath: move.to.path) else { skipped.append(move.to); continue }
            guard !fm.fileExists(atPath: move.from.path) else { skipped.append(move.to); continue }
            let destDir = move.from.deletingLastPathComponent()
            do {
                if !fm.fileExists(atPath: destDir.path) {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                }
                try fm.moveItem(at: move.to, to: move.from)
                restored.append((from: move.to, to: move.from))
            } catch {
                skipped.append(move.to)
            }
        }

        // 파일 복원 후 빈 폴더 삭제 (정리 시 생성된 폴더만)
        for folderPath in createdFolders {
            let folderURL = URL(fileURLWithPath: folderPath)
            guard fm.fileExists(atPath: folderPath) else { continue }
            let contents = (try? fm.contentsOfDirectory(atPath: folderPath)) ?? []
            if contents.isEmpty {
                try? fm.removeItem(at: folderURL)
            }
        }

        return (restored, skipped)
    }
}
