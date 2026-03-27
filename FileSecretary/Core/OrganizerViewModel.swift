import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

class OrganizerViewModel: ObservableObject {

    // MARK: - State

    @Published var targetFolders:  [URL] = []
    @Published var outputFolders:  [URL] = []
    @Published var categories:     [Category] = []
    @Published var excludeList:    ExcludeList = ExcludeList(keywords: [], extensions: [".DS_Store", ".gitignore"])
    @Published var etcOutputIdx:          Int = 0
    @Published var undoCount:             Int = 0
    @Published var isOrganizing:          Bool = false
    @Published var downloadResultMessage: String? = nil

    // MARK: - Dialog triggers

    @Published var showDuplicateDialog      = false
    @Published var showUncategorizedDialog  = false
    @Published var showConflictDialog       = false
    @Published var showExcludeListEditor    = false
    @Published var conflictFile:            URL? = nil
    @Published var conflictCategories:      [Category] = []

    // MARK: - Private

    private let fileOrganizer  = FileOrganizer()
    private let undoHistory    = UndoHistory()
    private var duplicateContinuation:          CheckedContinuation<DuplicateMode, Never>?
    private var pendingUncategorizedCompletion: ((UncategorizedResolution, Bool) -> Void)?
    private var pendingConflictCompletion:      ((ConflictResolution, Bool) -> Void)?

    @Published var uncategorizedMainFolderName: String? = nil

    // MARK: - Shared reference (used by menu commands)

    static weak var current: OrganizerViewModel?

    // MARK: - Init

    init() {
        OrganizerViewModel.current = self
        loadSettings()
    }

    // MARK: - Settings

    func loadSettings() {
        if let saved = SettingsManager.shared.load() {
            // outputIdx는 출력폴더 순서가 달라질 수 있으므로 재실행 시 리셋
            categories   = saved.categories.map { var c = $0; c.outputIdx = 0; return c }
            excludeList  = saved.excludeList
            etcOutputIdx = 0
        } else {
            loadDefaultRules()
        }
    }

    func loadDefaultRules() {
        guard let url = Bundle.main.url(forResource: "default_rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode(RulesData.self, from: data) else { return }
        categories  = rules.categories
        excludeList = rules.excludeList
    }

    func saveSettings() {
        let rules = RulesData(
            version: 1,
            categories: categories,
            outputFolders: outputFolders.map(\.path),
            excludeList: excludeList,
            etcOutputIdx: etcOutputIdx
        )
        SettingsManager.shared.save(rules)
    }

    func updateEtcOutputIdx(_ idx: Int) {
        etcOutputIdx = idx
        saveSettings()
    }

    func resetToDefaults() {
        SettingsManager.shared.resetToDefault()
        loadDefaultRules()
    }

    // MARK: - Target Folders

    func addTargetFolder(_ url: URL) {
        BookmarkManager.shared.saveBookmark(for: url)
        guard !targetFolders.contains(url) else { return }
        targetFolders.append(url)
    }

    func removeTargetFolder(at offsets: IndexSet) {
        targetFolders.remove(atOffsets: offsets)
    }

    // MARK: - Output Folders

    func addOutputFolder(_ url: URL) {
        BookmarkManager.shared.saveBookmark(for: url)
        guard !outputFolders.contains(url) else { return }
        outputFolders.append(url)
    }

    func removeOutputFolder(at offsets: IndexSet) {
        outputFolders.remove(atOffsets: offsets)
    }

    var outputFolderLabel: (Int) -> String { { idx in
        guard idx >= 0 else { return "?" }
        let letters = Array("ABCDEFGHIJKLMNOP")
        return idx < letters.count ? String(letters[idx]) : "\(idx + 1)"
    }}

    // MARK: - Categories

    func addCategory(_ cat: Category) {
        var c = cat
        c.num = (categories.map(\.num).max() ?? 0) + 1
        categories.append(c)
        saveSettings()
    }

    func updateCategory(_ cat: Category) {
        guard let idx = categories.firstIndex(where: { $0.id == cat.id }) else { return }
        categories[idx] = cat
        saveSettings()
    }

    func removeCategory(id: String) {
        categories.removeAll { $0.id == id }
        renumber()
        saveSettings()
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        renumber()
        saveSettings()
    }

    private func renumber() {
        for i in categories.indices { categories[i].num = i + 1 }
    }

    // MARK: - Open panels

    func openFolderPanel(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles           = false
        panel.canChooseDirectories     = true
        panel.allowsMultipleSelection  = false
        panel.prompt = "선택"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    // MARK: - Organize

    func startOrganize() {
        guard !isOrganizing else { return }
        Task { @MainActor in
            await runOrganize()
        }
    }

    // Called by DuplicateFileDialog confirm
    func confirmDuplicate(_ mode: DuplicateMode) {
        showDuplicateDialog = false
        duplicateContinuation?.resume(returning: mode)
        duplicateContinuation = nil
    }

    // Called by DuplicateFileDialog cancel → treat as skip
    func cancelDuplicate() {
        showDuplicateDialog = false
        duplicateContinuation?.resume(returning: .skip)
        duplicateContinuation = nil
    }

    func confirmUncategorized(_ resolution: UncategorizedResolution, applyToAll: Bool = false) {
        pendingUncategorizedCompletion?(resolution, applyToAll)
        pendingUncategorizedCompletion = nil
        showUncategorizedDialog = false
    }

    func resolveConflict(_ resolution: ConflictResolution, applyToAll: Bool = false) {
        pendingConflictCompletion?(resolution, applyToAll)
        pendingConflictCompletion = nil
        showConflictDialog = false
        conflictFile = nil
        conflictCategories = []
    }

    @MainActor
    private func askConflict(for file: URL, categories: [Category]) async -> (ConflictResolution, Bool) {
        conflictFile = file
        conflictCategories = categories
        showConflictDialog = true
        return await withCheckedContinuation { continuation in
            pendingConflictCompletion = { continuation.resume(returning: ($0, $1)) }
        }
    }

    @MainActor
    private func askUncategorized(for file: URL) async -> (UncategorizedResolution, Bool) {
        conflictFile = file
        uncategorizedMainFolderName = outputFolders.first?.lastPathComponent
        showUncategorizedDialog = true
        return await withCheckedContinuation { continuation in
            pendingUncategorizedCompletion = { continuation.resume(returning: ($0, $1)) }
        }
    }

    /// Pauses organize loop and shows the duplicate dialog for the given file.
    /// Resumes when the user picks a mode (or cancels → .skip).
    @MainActor
    private func askDuplicateMode(for file: URL) async -> DuplicateMode {
        conflictFile = file
        showDuplicateDialog = true
        return await withCheckedContinuation { continuation in
            duplicateContinuation = continuation
        }
    }

    @MainActor
    private func runOrganize() async {
        isOrganizing = true
        defer {
            isOrganizing = false
            conflictFile = nil
        }

        let outputs    = outputFolders
        let cats       = categories
        let excl       = excludeList
        let allTargets = targetFolders
        let etcIdx     = etcOutputIdx

        // 중복 파일 처리: 전체 정리 1회당 1번만 물어봄
        var cachedDuplicateMode: DuplicateMode? = nil
        var combinedMoved:   [(from: URL, to: URL)] = []
        var combinedSkipped: [URL] = []
        var combinedErrors:  [(file: URL, error: Error)] = []

        for folder in allTargets {
            let secureFolder  = BookmarkManager.shared.restoreURL(for: folder.path) ?? folder
            let secureOutputs = outputs.map { BookmarkManager.shared.restoreURL(for: $0.path) ?? $0 }

            BookmarkManager.shared.startAccessing(secureFolder)
            secureOutputs.forEach { BookmarkManager.shared.startAccessing($0) }
            defer {
                BookmarkManager.shared.stopAccessing(secureFolder)
                secureOutputs.forEach { BookmarkManager.shared.stopAccessing($0) }
            }

            // 폴더별로 캐시 리셋: 같은 충돌 조합이면 1번만, 기타는 이 폴더 안에서 1번만
            var cachedConflicts: [Set<String>: ConflictResolution] = [:]
            var cachedUncategorized: UncategorizedResolution? = nil

            guard let result = try? await fileOrganizer.organize(
                targetFolder: secureFolder,
                categories: cats,
                excludeList: excl,
                outputFolders: secureOutputs,
                etcOutputIdx: etcIdx,
                duplicateHandler: { [weak self] file in
                    guard let self else { return .skip }
                    if let mode = cachedDuplicateMode { return mode }
                    let mode = await self.askDuplicateMode(for: file)
                    cachedDuplicateMode = mode
                    return mode
                },
                conflictHandler: { [weak self] file, matchedCats in
                    guard let self else { return .useFirst }
                    let key = Set(matchedCats.map(\.id))
                    if let cached = cachedConflicts[key] { return cached }
                    let (resolution, applyToAll) = await self.askConflict(for: file, categories: matchedCats)
                    if applyToAll { cachedConflicts[key] = resolution }
                    return resolution
                },
                uncategorizedHandler: { [weak self] file in
                    guard let self else { return .leaveInPlace }
                    if let cached = cachedUncategorized { return cached }
                    let (resolution, applyToAll) = await self.askUncategorized(for: file)
                    if applyToAll { cachedUncategorized = resolution }
                    return resolution
                }
            ) else { continue }

            combinedMoved   += result.moved
            combinedSkipped += result.skipped
            combinedErrors  += result.errors
        }

        // 전체 정리를 1개의 undo 단계로 기록 (멀티폴더도 한 번에 되돌리기)
        var combined = OrganizeResult()
        combined.moved   = combinedMoved
        combined.skipped = combinedSkipped
        combined.errors  = combinedErrors
        undoHistory.push(combined)
        undoCount = undoHistory.count
        LogWriter.shared.logOrganizeResult(combined, targetFolders: allTargets, outputFolders: outputs)
    }

    // MARK: - Undo

    func performUndo() {
        guard undoCount > 0 else { return }
        Task { @MainActor in
            let allFolders  = targetFolders + outputFolders
            let secureURLs  = allFolders.map { BookmarkManager.shared.restoreURL(for: $0.path) ?? $0 }
            secureURLs.forEach { BookmarkManager.shared.startAccessing($0) }
            defer { secureURLs.forEach { BookmarkManager.shared.stopAccessing($0) } }
            let result = undoHistory.undo()
            undoCount = undoHistory.count
            LogWriter.shared.logUndoResult(restored: result.restored, skipped: result.skipped)
        }
    }

    // MARK: - One-click Downloads

    func organizeDownloads() {
        Task { @MainActor in
            isOrganizing = true
            downloadResultMessage = nil
            var cachedMode: DuplicateMode? = nil

            let downloadsURL = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                .resolvingSymlinksInPath()
            do {
                let result = try await fileOrganizer.organizeDownloads(
                    at: downloadsURL,
                    duplicateHandler: { [weak self] file in
                        guard let self else { return .addNumber }
                        if let mode = cachedMode { return mode }
                        let mode = await self.askDuplicateMode(for: file)
                        cachedMode = mode
                        return mode
                    }
                )
                undoHistory.push(result)
                undoCount = undoHistory.count
                LogWriter.shared.logOrganizeResult(result, targetFolders: [downloadsURL], outputFolders: [])
                downloadResultMessage = result.movedCount > 0
                    ? "완료 · \(result.movedCount)개 이동"
                    : "정리할 파일 없음"
            } catch {
                LogWriter.shared.log("다운로드 정리 오류: \(error.localizedDescription)")
                downloadResultMessage = "오류 발생 (로그 확인)"
            }
            isOrganizing = false
            conflictFile = nil
        }
    }

    // MARK: - Preset

    func savePreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "FileSecretary_Preset.json"
        panel.prompt = "저장"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let rules = RulesData(
                version: 1,
                categories: self.categories,
                outputFolders: self.outputFolders.map(\.path),
                excludeList: self.excludeList
            )
            try? SettingsManager.shared.savePreset(rules, to: url)
        }
    }

    func loadPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "불러오기"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let rules = try? SettingsManager.shared.loadPreset(from: url) else { return }
            self.categories  = rules.categories
            self.excludeList = rules.excludeList
            self.saveSettings()
        }
    }

    // MARK: - Log

    func openLogFolder() {
        NSWorkspace.shared.open(LogWriter.shared.logFolderURL)
    }

    func exportLogXLSX() {
        guard !LogWriter.shared.entries.isEmpty else { return }
        let panel = NSSavePanel()
        if let xlsxType = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [xlsxType]
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = fmt.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        panel.nameFieldStringValue = "FileSecretary_Log_\(dateStr).xlsx"
        panel.prompt = "내보내기"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? LogWriter.shared.exportXLSX(to: url)
        }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
