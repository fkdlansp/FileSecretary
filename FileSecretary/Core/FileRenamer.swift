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
        var failed: [(url: URL, error: String)] = []
    }

    // 주어진 파라미터로 단일 아이템의 목표 파일명 계산
    func computeTargetName(item: RenameItem,
                           index: Int,
                           digits: Int,
                           startNumber: Int,
                           unifiedBaseName: String,
                           unifyMode: Int,
                           useNumbering: Bool) -> String {
        let trimmedBase = unifiedBaseName.trimmingCharacters(in: .whitespaces)
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
        if useNumbering {
            let numStr = String(format: "%0\(digits)d", startNumber + index)
            return "\(numStr)_\(base)\(ext)"
        } else {
            return "\(base)\(ext)"
        }
    }

    func apply(items: [RenameItem],
               digits: Int,
               startNumber: Int,
               unifiedBaseName: String,
               unifyMode: Int = 0,
               useNumbering: Bool = true,
               resolveDuplicates: Bool = false) -> RenameResult {
        var result = RenameResult()

        print("[FileRenamer] apply 시작 — 대상 \(items.count)개, 번호사용=\(useNumbering), 중복해결=\(resolveDuplicates)")

        // 1단계: 모든 목표 파일명 계산
        var targetNames: [String] = items.enumerated().map { (i, item) in
            computeTargetName(item: item, index: i, digits: digits, startNumber: startNumber,
                              unifiedBaseName: unifiedBaseName, unifyMode: unifyMode, useNumbering: useNumbering)
        }

        // 2단계: 중복 해결 (자동 넘버링)
        if resolveDuplicates {
            var seenCount: [String: Int] = [:]
            for (i, name) in targetNames.enumerated() {
                seenCount[name, default: 0] += 1
                let count = seenCount[name]!
                if count > 1 {
                    let ext = items[i].ext.isEmpty ? "" : ".\(items[i].ext)"
                    let base = (!ext.isEmpty && name.hasSuffix(ext))
                        ? String(name.dropLast(ext.count))
                        : name
                    targetNames[i] = "\(base)(\(count))\(ext)"
                    print("[FileRenamer] 중복 해결: \(name) → \(targetNames[i])")
                }
            }
        }

        // 3단계: 실제 rename
        for (i, item) in items.enumerated() {
            let newName = targetNames[i]
            let destURL = item.originalURL
                .deletingLastPathComponent()
                .appendingPathComponent(newName)

            print("[FileRenamer] [\(i)] \(item.originalURL.lastPathComponent) → \(newName)")

            guard destURL != item.originalURL else {
                print("[FileRenamer]   → 이름 동일, 건너뜀")
                continue
            }

            do {
                try FileManager.default.moveItem(at: item.originalURL, to: destURL)
                result.renamed.append((from: item.originalURL, to: destURL))
                print("[FileRenamer]   → 성공")
            } catch {
                result.failed.append((url: item.originalURL, error: error.localizedDescription))
                print("[FileRenamer]   → 실패: \(error.localizedDescription)")
            }
        }

        print("[FileRenamer] 완료 — 성공 \(result.renamed.count)개, 실패 \(result.failed.count)개")
        return result
    }
}
