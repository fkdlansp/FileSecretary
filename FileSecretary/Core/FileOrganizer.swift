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

        // 출력폴더별 상대 넘버링 맵 사전 계산
        let folderNumberMap = buildFolderNumberMap(
            files: files, categories: categories, excludeList: excludeList,
            outputFolders: outputFolders, targetFolder: targetFolder
        )

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

            // 실제 해당 출력폴더에 들어오는 카테고리 기준 상대 넘버링
            let folderName: String
            if let cat = chosenCategory {
                if let relNum = folderNumberMap[destination.path]?[cat.id] {
                    folderName = String(format: "%02d_%@", relNum, cat.name)
                } else {
                    folderName = cat.folderName
                }
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

        // 기존 출력폴더의 번호가 틀어진 폴더들 재정렬
        reconcileFolderNumbers(
            destPaths: Array(folderNumberMap.keys),
            folderNumberMap: folderNumberMap,
            categories: categories
        )

        return result
    }

    // MARK: - Folder numbering helpers

    /// 사전 스캔: 각 목적지 폴더에 어떤 카테고리가 들어올지 파악해 상대 번호 맵 반환
    private func buildFolderNumberMap(
        files: [URL],
        categories: [Category],
        excludeList: ExcludeList,
        outputFolders: [URL],
        targetFolder: URL
    ) -> [String: [String: Int]] {

        let fm = FileManager.default
        var catIdsPerDest: [String: Set<String>] = [:]

        // 신규 파일 스캔
        for file in files {
            if ruleEngine.isExcluded(file: file, excludeList: excludeList) { continue }
            let matches = ruleEngine.evaluate(file: file, categories: categories)
            guard let cat = matches.first else { continue }
            let dest: URL = (cat.outputIdx > 0 && cat.outputIdx - 1 < outputFolders.count)
                ? outputFolders[cat.outputIdx - 1] : targetFolder
            catIdsPerDest[dest.path, default: []].insert(cat.id)
        }

        // 기존 폴더 스캔 (이전 정리 결과)
        let catByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })
        for destPath in catIdsPerDest.keys {
            let destURL = URL(fileURLWithPath: destPath)
            let items = (try? fm.contentsOfDirectory(at: destURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for item in items {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let name = item.lastPathComponent
                guard name.count > 3,
                      String(name.prefix(2)).allSatisfy({ $0.isNumber }),
                      name.dropFirst(2).first == "_" else { continue }
                let catName = String(name.dropFirst(3))
                if let cat = catByName[catName] { catIdsPerDest[destPath]!.insert(cat.id) }
            }
        }

        // 카테고리 num 순 정렬 후 상대 번호 부여
        var result: [String: [String: Int]] = [:]
        for (destPath, catIds) in catIdsPerDest {
            let sorted = categories.filter { catIds.contains($0.id) }.sorted { $0.num < $1.num }
            result[destPath] = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.id, $0 + 1) })
        }
        return result
    }

    /// 기존 출력폴더 내 번호가 바뀐 폴더를 재정렬 (temp rename으로 충돌 방지)
    private func reconcileFolderNumbers(
        destPaths: [String],
        folderNumberMap: [String: [String: Int]],
        categories: [Category]
    ) {
        let fm = FileManager.default
        let catByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })

        for destPath in destPaths {
            guard let numMap = folderNumberMap[destPath],
                  fm.fileExists(atPath: destPath) else { continue }
            let destURL = URL(fileURLWithPath: destPath)
            let items = (try? fm.contentsOfDirectory(at: destURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

            var toRename: [(from: URL, newName: String)] = []
            for item in items {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let name = item.lastPathComponent
                guard name.count > 3,
                      String(name.prefix(2)).allSatisfy({ $0.isNumber }),
                      name.dropFirst(2).first == "_" else { continue }
                let catName = String(name.dropFirst(3))
                guard let cat = catByName[catName], let newNum = numMap[cat.id] else { continue }
                let newName = String(format: "%02d_%@", newNum, cat.name)
                if newName != name { toRename.append((from: item, newName: newName)) }
            }

            // 1단계: 임시 이름으로 이동 (충돌 방지)
            var pending: [(temp: URL, finalName: String)] = []
            for r in toRename {
                let tmp = destURL.appendingPathComponent("__fstmp_\(UUID().uuidString)")
                if (try? fm.moveItem(at: r.from, to: tmp)) != nil {
                    pending.append((temp: tmp, finalName: r.newName))
                }
            }
            // 2단계: 최종 이름으로 이동 (이미 있으면 병합)
            for p in pending {
                let finalURL = destURL.appendingPathComponent(p.finalName)
                if fm.fileExists(atPath: finalURL.path) {
                    let contents = (try? fm.contentsOfDirectory(at: p.temp, includingPropertiesForKeys: nil, options: [])) ?? []
                    for f in contents {
                        let dst = finalURL.appendingPathComponent(f.lastPathComponent)
                        if !fm.fileExists(atPath: dst.path) { try? fm.moveItem(at: f, to: dst) }
                    }
                    try? fm.removeItem(at: p.temp)
                } else {
                    try? fm.moveItem(at: p.temp, to: finalURL)
                }
            }
        }
    }

    /// One-click Downloads cleanup — type-based, no numbering, default folders.
    @discardableResult
    func organizeDownloads(
        at downloads: URL = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
            .resolvingSymlinksInPath(),
        duplicateHandler: @escaping (URL) async -> DuplicateMode = { _ in .addNumber },
        conflictHandler: @escaping (URL, [Category]) async -> ConflictResolution = { _, _ in .useFirst }
    ) async throws -> OrganizeResult {

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
