import Foundation

class LogWriter {
    static let shared = LogWriter()
    private init() {}

    private(set) var entries: [LogEntry] = []

    var logFolderURL: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let dir = lib.appendingPathComponent("Logs/FileSecretary", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var todayLogURL: URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return logFolderURL.appendingPathComponent("\(f.string(from: Date())).log")
    }

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
        let labels   = ["A","B","C","D"]
        let now      = Date()
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

        // Accumulate entries for xlsx export
        for move in result.moved {
            entries.append(LogEntry(timestamp: now, action: "이동",
                fileName: move.from.lastPathComponent,
                sourcePath: move.from.path, destPath: move.to.path,
                errorMessage: "", targetFolders: targetStr, outputFolders: outputStr))
        }
        for skip in result.skipped {
            entries.append(LogEntry(timestamp: now, action: "건너뜀",
                fileName: skip.lastPathComponent,
                sourcePath: skip.path, destPath: "",
                errorMessage: "", targetFolders: targetStr, outputFolders: outputStr))
        }
        for err in result.errors {
            entries.append(LogEntry(timestamp: now, action: "오류",
                fileName: err.file.lastPathComponent,
                sourcePath: err.file.path, destPath: "",
                errorMessage: err.error.localizedDescription,
                targetFolders: targetStr, outputFolders: outputStr))
        }
    }

    func exportXLSX(to url: URL) throws {
        try XLSXExporter.export(entries: entries, to: url)
    }
}

private extension DateFormatter {
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
