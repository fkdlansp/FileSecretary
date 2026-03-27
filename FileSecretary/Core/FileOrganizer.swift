import Foundation

// MARK: - Organize Result

struct OrganizeResult {
    var moved:     [(from: URL, to: URL)] = []
    var skipped:   [URL] = []
    var conflicts: [(file: URL, categories: [Category])] = []
    var errors:    [(file: URL, error: Error)] = []

    var movedCount:   Int { moved.count }
    var skippedCount: Int { skipped.count }
}

// MARK: - Conflict Resolution

enum ConflictResolution {
    case useFirst
    case useCategory(Category)
    case skip
}

// MARK: - Uncategorized Resolution

enum UncategorizedResolution {
    case moveToMain      // 메인 출력 폴더의 기타로 이동
    case leaveInPlace    // 해당 폴더에 그대로 남기기
    case moveToLocalEtc  // 해당 대상 폴더 안에 기타 폴더 만들어서 이동
}

// MARK: - FileOrganizer

class FileOrganizer {

    private let ruleEngine         = RuleEngine()
    private let duplicateResolver  = DuplicateResolver()

    /// Scan regular files in a folder (non-recursive).
    func scanFiles(in folder: URL) throws -> [URL] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    /// Organize files from `targetFolder` into output folders routed per-category.
    ///
    /// - Parameters:
    ///   - outputFolders: Ordered list of output folders [A, B, C, D]. Category.outputIdx 1=A, 2=B, …
    ///                    outputIdx 0 (개별 모드) keeps files inside targetFolder.
    ///   - duplicateHandler: Called only when a duplicate filename exists at destination. Returns how to handle it.
    ///   - conflictHandler: Called when a file matches multiple categories. Returns which category to use.
    ///   - uncategorizedHandler: Called when a file matches no category. Returns true to move to 기타.
    @discardableResult
    func organize(
        targetFolder:         URL,
        categories:           [Category],
        excludeList:          ExcludeList,
        outputFolders:        [URL],
        etcOutputIdx:         Int = 0,
        duplicateHandler:     @escaping (URL) async -> DuplicateMode,
        conflictHandler:      @escaping (URL, [Category]) async -> ConflictResolution,
        uncategorizedHandler: @escaping (URL) async -> UncategorizedResolution
    ) async throws -> OrganizeResult {

        var result = OrganizeResult()
        let fm    = FileManager.default
        let files = try scanFiles(in: targetFolder)

        for file in files {
            // Exclude list check
            if ruleEngine.isExcluded(file: file, excludeList: excludeList) {
                result.skipped.append(file)
                continue
            }

            let matches = ruleEngine.evaluate(file: file, categories: categories)

            let chosenCategory: Category?
            var uncategorizedDest: URL? = nil  // 기타 케이스 목적지 override

            if matches.isEmpty {
                if etcOutputIdx > 0, etcOutputIdx - 1 < outputFolders.count {
                    // 기타 출력폴더가 지정된 경우 자동 라우팅 (다이얼로그 없음)
                    uncategorizedDest = outputFolders[etcOutputIdx - 1]
                } else {
                    switch await uncategorizedHandler(file) {
                    case .leaveInPlace:
                        result.skipped.append(file)
                        continue
                    case .moveToMain:
                        uncategorizedDest = outputFolders.first ?? targetFolder
                    case .moveToLocalEtc:
                        uncategorizedDest = targetFolder
                    }
                }
                chosenCategory = nil  // → 기타 폴더
            } else if matches.count == 1 {
                chosenCategory = matches[0]
            } else {
                result.conflicts.append((file: file, categories: matches))
                switch await conflictHandler(file, matches) {
                case .useFirst:             chosenCategory = matches[0]
                case .useCategory(let cat): chosenCategory = cat
                case .skip:
                    result.skipped.append(file)
                    continue
                }
            }

            // Route to the correct output folder based on category.outputIdx.
            // outputIdx 0 or out-of-range → 개별 모드 (targetFolder)
            let destination: URL
            if let override = uncategorizedDest {
                destination = override
            } else if let cat = chosenCategory,
               cat.outputIdx > 0,
               cat.outputIdx - 1 < outputFolders.count {
                destination = outputFolders[cat.outputIdx - 1]
            } else {
                destination = targetFolder
            }

            // 출력폴더가 2개 이상이면 넘버링 없이 카테고리명만 사용
            let folderName: String
            if let cat = chosenCategory {
                folderName = outputFolders.count > 1 ? cat.name : cat.folderName
            } else {
                folderName = "기타"
            }
            let destFolder = destination.appendingPathComponent(folderName, isDirectory: true)

            do {
                if !fm.fileExists(atPath: destFolder.path) {
                    try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
                }

                let destFile = destFolder.appendingPathComponent(file.lastPathComponent)

                // Only ask when destination file actually exists
                let mode: DuplicateMode = fm.fileExists(atPath: destFile.path)
                    ? await duplicateHandler(file)
                    : .addNumber

                guard let actualDest = try duplicateResolver.resolve(
                    source: file, destination: destFile, mode: mode
                ) else {
                    result.skipped.append(file)
                    continue
                }

                try fm.moveItem(at: file, to: actualDest)
                result.moved.append((from: file, to: actualDest))
            } catch {
                result.errors.append((file: file, error: error))
            }
        }

        return result
    }

    /// One-click Downloads cleanup — type-based, no numbering, default folders.
    @discardableResult
    func organizeDownloads(
        duplicateHandler: @escaping (URL) async -> DuplicateMode = { _ in .addNumber },
        conflictHandler: @escaping (URL, [Category]) async -> ConflictResolution = { _, _ in .useFirst }
    ) async throws -> OrganizeResult {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")

        let categories: [Category] = FileTypeCategory.allCases.enumerated().map { i, ft in
            Category(
                id: ft.rawValue,
                num: i + 1,
                name: ft.rawValue,
                conditionType: .type,
                types: [ft.rawValue],
                keywords: [],
                logic: nil,
                outputIdx: 0
            )
        }
        let excludeList = ExcludeList(keywords: [], extensions: [".DS_Store", ".gitignore"])

        return try await organize(
            targetFolder: downloads,
            categories: categories,
            excludeList: excludeList,
            outputFolders: [],
            duplicateHandler: duplicateHandler,
            conflictHandler: conflictHandler,
            uncategorizedHandler: { _ in .moveToLocalEtc }
        )
    }
}
