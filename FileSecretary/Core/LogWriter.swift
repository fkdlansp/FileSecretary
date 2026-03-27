import Foundation

class LogWriter {
    static let shared = LogWriter()
    private init() {}

    private(set) var entries: [LogEntry] = []

    // MARK: - Folder URLs

    var logFolderURL: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let dir = lib.appendingPathComponent("Logs/FileSecretary", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var logSubfolderURL: URL {
        let dir = logFolderURL.appendingPathComponent("log", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var xlsxSubfolderURL: URL {
        let dir = logFolderURL.appendingPathComponent("xlsx", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var todayLogURL: URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return logSubfolderURL.appendingPathComponent("\(f.string(from: Date())).log")
    }

    // MARK: - Logging

    func log(_ message: String) {
        let ts = DateFormatter.logTimestamp.string(from: Date())
        let line = "[\(ts)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = todayLogURL
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    func logOrganizeResult(_ result: OrganizeResult, targetFolders: [URL], outputFolders: [URL]) {
        let labels    = ["A","B","C","D"]
        let now       = Date()
        let targetStr = targetFolders.map(\.path).joined(separator: ", ")
        let outputStr = outputFolders.enumerated()
            .map { "\(labels[safe: $0] ?? String($0+1)): \($1.path)" }
            .joined(separator: ", ")

        log("===== 정리 시작 =====")
        targetFolders.forEach { log("대상 폴더: \($0.path)") }
        for (i, out) in outputFolders.enumerated() {
            log("출력 폴더 \(labels[safe: i] ?? String(i+1)): \(out.path)")
        }
        result.moved.forEach   { log("이동: \($0.from.lastPathComponent) → \($0.to.path)") }
        result.skipped.forEach { log("건너뜀: \($0.lastPathComponent)") }
        result.errors.forEach  { log("오류: \($0.file.lastPathComponent) — \($0.error.localizedDescription)") }
        log("===== 정리 완료: 이동 \(result.movedCount)개 / 건너뜀 \(result.skippedCount)개 =====")

        // Accumulate entries
        var runEntries: [LogEntry] = []
        for move in result.moved {
            let e = LogEntry(timestamp: now, action: "이동",
                fileName: move.from.lastPathComponent,
                sourcePath: move.from.path, destPath: move.to.path,
                errorMessage: "", targetFolders: targetStr, outputFolders: outputStr)
            entries.append(e); runEntries.append(e)
        }
        for skip in result.skipped {
            let e = LogEntry(timestamp: now, action: "건너뜀",
                fileName: skip.lastPathComponent,
                sourcePath: skip.path, destPath: "",
                errorMessage: "", targetFolders: targetStr, outputFolders: outputStr)
            entries.append(e); runEntries.append(e)
        }
        for err in result.errors {
            let e = LogEntry(timestamp: now, action: "오류",
                fileName: err.file.lastPathComponent,
                sourcePath: err.file.path, destPath: "",
                errorMessage: err.error.localizedDescription,
                targetFolders: targetStr, outputFolders: outputStr)
            entries.append(e); runEntries.append(e)
        }

        // Auto-save xlsx for this run
        if !runEntries.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "\(f.string(from: now)).xlsx"
            let xlsxURL  = xlsxSubfolderURL.appendingPathComponent(filename)
            try? XLSXExporter.export(entries: runEntries, to: xlsxURL)
        }
    }

    func logUndoResult(restored: [(from: URL, to: URL)], skipped: [URL]) {
        let now = Date()
        log("===== 되돌리기 시작 =====")
        restored.forEach { log("되돌리기: \($0.from.lastPathComponent) ← \($0.to.path)") }
        skipped.forEach  { log("건너뜀: \($0.lastPathComponent)") }
        log("===== 되돌리기 완료: 복원 \(restored.count)개 / 건너뜀 \(skipped.count)개 =====")

        var runEntries: [LogEntry] = []
        for move in restored {
            let e = LogEntry(timestamp: now, action: "되돌리기",
                fileName: move.from.lastPathComponent,
                sourcePath: move.from.path, destPath: move.to.path,
                errorMessage: "", targetFolders: "", outputFolders: "")
            entries.append(e); runEntries.append(e)
        }
        for url in skipped {
            let e = LogEntry(timestamp: now, action: "건너뜀",
                fileName: url.lastPathComponent,
                sourcePath: url.path, destPath: "",
                errorMessage: "", targetFolders: "", outputFolders: "")
            entries.append(e); runEntries.append(e)
        }

        if !runEntries.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let xlsxURL = xlsxSubfolderURL.appendingPathComponent("undo_\(f.string(from: now)).xlsx")
            try? XLSXExporter.export(entries: runEntries, to: xlsxURL)
        }
    }

    func logRenameResult(renamed: [(from: URL, to: URL)], failed: [URL], folder: URL) {
        let now = Date()
        log("===== 파일명 변경 시작 =====")
        log("대상 폴더: \(folder.path)")
        renamed.forEach { log("변경: \($0.from.lastPathComponent) → \($0.to.lastPathComponent)") }
        failed.forEach  { log("실패: \($0.lastPathComponent)") }
        log("===== 파일명 변경 완료: 변경 \(renamed.count)개 / 실패 \(failed.count)개 =====")

        var runEntries: [LogEntry] = []
        for pair in renamed {
            let e = LogEntry(timestamp: now, action: "파일명 변경",
                fileName: pair.from.lastPathComponent,
                sourcePath: pair.from.path, destPath: pair.to.path,
                errorMessage: "", targetFolders: folder.path, outputFolders: "")
            entries.append(e); runEntries.append(e)
        }
        for url in failed {
            let e = LogEntry(timestamp: now, action: "변경 실패",
                fileName: url.lastPathComponent,
                sourcePath: url.path, destPath: "",
                errorMessage: "", targetFolders: folder.path, outputFolders: "")
            entries.append(e); runEntries.append(e)
        }

        if !runEntries.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let xlsxURL = xlsxSubfolderURL.appendingPathComponent("rename_\(f.string(from: now)).xlsx")
            try? XLSXExporter.export(entries: runEntries, to: xlsxURL)
        }
    }

    // Manual full-session export
    func exportXLSX(to url: URL) throws {
        try XLSXExporter.export(entries: entries, to: url)
    }
}

extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
