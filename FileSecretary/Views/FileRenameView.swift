import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - RenameViewModel

private class RenameViewModel: ObservableObject {

    @Published var folderURL: URL? = nil
    @Published var fileMode: Bool = false   // true = 개별 파일 드래그 모드
    @Published var fileModeCount: Int = 0   // 파일 모드 시 파일 개수 (헤더 표시용)
    @Published var items: [RenameItem] = []
    @Published var digits: Int = 3
    @Published var startNumberText: String = ""
    @Published var unifiedBaseName: String = ""
    @Published var unifyMode: Int = 0       // 0 = 완전 교체, 1 = 통일명(원본)

    var useNumbering: Bool { Int(startNumberText.trimmingCharacters(in: .whitespaces)) != nil }
    var startNumber: Int { Int(startNumberText.trimmingCharacters(in: .whitespaces)) ?? 1 }
    @Published var isApplying: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: Duplicate alert
    @Published var showDuplicateAlert: Bool = false
    var duplicateAlertMessage: String = ""
    private var pendingResolveDuplicates: Bool = false

    private let renamer = FileRenamer()
    private var snapshot: [RenameItem] = []
    private var undoStack: [[(from: URL, to: URL)]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var undoCount: Int { undoStack.count }

    // MARK: Folder loading

    func loadFolder(_ url: URL) {
        print("[RenameVM] loadFolder: \(url.path)")
        // 현재 접근 권한이 있는 동안 북마크 저장
        BookmarkManager.shared.saveBookmark(for: url)
        print("[RenameVM] 폴더 북마크 저장: \(url.lastPathComponent)")
        fileMode = false
        folderURL = url
        errorMessage = nil
        do {
            let all = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let regular = all
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            items = regular.map { RenameItem(originalURL: $0) }
            print("[RenameVM] loadFolder: \(items.count)개 파일 로드됨")
        } catch {
            print("[RenameVM] loadFolder 실패: \(error)")
            items = []
        }
        snapshot = items
        undoStack = []
    }

    // MARK: File loading (개별 파일 드래그)

    func loadFiles(_ urls: [URL]) {
        print("[RenameVM] loadFiles: 입력 \(urls.count)개")
        fileMode = true
        errorMessage = nil
        let regular = urls
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        items = regular.map { RenameItem(originalURL: $0) }
        snapshot = items
        fileModeCount = items.count
        undoStack = []
        // 현재 접근 권한이 있는 동안 부모 폴더 북마크 저장
        let parentURLs = Set(regular.map { $0.deletingLastPathComponent() })
        for parent in parentURLs {
            BookmarkManager.shared.saveBookmark(for: parent)
            print("[RenameVM] 부모 폴더 북마크 저장: \(parent.lastPathComponent)")
        }
        // 모든 파일이 같은 폴더면 folderURL 표시용으로만 사용
        folderURL = parentURLs.count == 1 ? parentURLs.first : nil
        print("[RenameVM] loadFiles: \(items.count)개 로드, 폴더=\(folderURL?.path ?? "여러 폴더")")
    }

    // MARK: Append (기존 목록에 추가 — 리셋 없음)

    func appendURLs(_ urls: [URL]) {
        print("[RenameVM] appendURLs: 추가 요청 \(urls.count)개 URL")
        var isDir: ObjCBool = false
        let isDirFn: (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        let existingURLs = Set(items.map { $0.originalURL })
        var newFiles: [URL] = []

        for url in urls {
            if isDirFn(url) {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for f in contents {
                    if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                       !existingURLs.contains(f) {
                        newFiles.append(f)
                    }
                }
            } else if !existingURLs.contains(url) {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    newFiles.append(url)
                }
            }
        }

        guard !newFiles.isEmpty else {
            print("[RenameVM] appendURLs: 추가할 새 파일 없음 (이미 목록에 있거나 비어있음)")
            return
        }

        let sorted = newFiles.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let newItems = sorted.map { RenameItem(originalURL: $0) }
        items.append(contentsOf: newItems)
        snapshot.append(contentsOf: newItems)
        // 새로 추가된 파일들의 부모 폴더 북마크 저장 (현재 접근 권한 있는 동안)
        let newParentURLs = Set(newFiles.map { $0.deletingLastPathComponent() })
        for parent in newParentURLs {
            BookmarkManager.shared.saveBookmark(for: parent)
            print("[RenameVM] appendURLs 부모 폴더 북마크 저장: \(parent.lastPathComponent)")
        }
        fileMode = true
        fileModeCount = items.count
        let allParents = Set(items.map { $0.originalURL.deletingLastPathComponent() })
        folderURL = allParents.count == 1 ? allParents.first : nil
        print("[RenameVM] appendURLs: \(newItems.count)개 추가, 총 \(items.count)개")
    }

    // MARK: Select all

    var allSelected: Bool { items.isEmpty ? false : items.allSatisfy { $0.isSelected } }

    func toggleSelectAll() {
        let newVal = !allSelected
        for i in items.indices { items[i].isSelected = newVal }
    }

    // MARK: Preview

    func previewName(for item: RenameItem, at index: Int) -> String {
        guard item.isSelected else { return item.displayName }

        // 선택된 항목 기준으로 순번 재계산
        let selectedItems = items.filter { $0.isSelected }
        let selectedIndex = selectedItems.firstIndex(where: { $0.id == item.id }) ?? index

        return computePreviewName(item: item, selectedIndex: selectedIndex)
    }

    // 내부 공용 미리보기 계산 (중복 검사용)
    private func computePreviewName(item: RenameItem, selectedIndex: Int) -> String {
        let trimmed = unifiedBaseName.trimmingCharacters(in: .whitespaces)
        let base: String
        if !trimmed.isEmpty {
            if unifyMode == 0 {
                base = trimmed
            } else {
                let originalBase = item.originalURL.deletingPathExtension().lastPathComponent
                base = "\(trimmed)(\(originalBase))"
            }
        } else {
            base = item.baseName
        }
        let ext = item.ext.isEmpty ? "" : ".\(item.ext)"
        if useNumbering {
            let numStr = String(format: "%0\(digits)d", startNumber + selectedIndex)
            return "\(numStr)_\(base)\(ext)"
        } else {
            return "\(base)\(ext)"
        }
    }

    // MARK: Actions

    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        snapshot.removeAll { $0.id == id }
        updateAfterRemove()
    }

    func removeSelectedItems() {
        let selectedIDs = Set(items.filter { $0.isSelected }.map { $0.id })
        items.removeAll { selectedIDs.contains($0.id) }
        snapshot.removeAll { selectedIDs.contains($0.id) }
        updateAfterRemove()
    }

    private func updateAfterRemove() {
        if fileMode { fileModeCount = items.count }
        let parents = Set(items.map { $0.originalURL.deletingLastPathComponent().path })
        folderURL = parents.count == 1 ? items.first?.originalURL.deletingLastPathComponent() : nil
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func reset() {
        items = snapshot
        digits = 3
        startNumberText = ""
        unifiedBaseName = ""
        unifyMode = 0
        errorMessage = nil
        undoStack = []
    }

    func clearFolder() {
        fileMode = false
        folderURL = nil
        items = []
        snapshot = []
        undoStack = []
        errorMessage = nil
    }

    // MARK: Duplicate check → apply

    func checkAndApply() {
        let selected = items.filter { $0.isSelected }
        guard !selected.isEmpty else {
            print("[RenameVM] checkAndApply: 선택된 항목 없음")
            return
        }

        // 미리보기 이름 계산
        var nameToIndices: [String: [Int]] = [:]
        for (i, item) in selected.enumerated() {
            let name = computePreviewName(item: item, selectedIndex: i)
            nameToIndices[name, default: []].append(i)
        }

        let duplicateNames = nameToIndices.filter { $0.value.count > 1 }.map { $0.key }.sorted()

        if duplicateNames.isEmpty {
            print("[RenameVM] checkAndApply: 중복 없음, 바로 적용")
            apply(resolveDuplicates: false)
        } else {
            print("[RenameVM] checkAndApply: 중복 \(duplicateNames.count)건 감지 — \(duplicateNames)")
            let preview = duplicateNames.prefix(3).map { "• \($0)" }.joined(separator: "\n")
            let more = duplicateNames.count > 3 ? "\n외 \(duplicateNames.count - 3)건 더" : ""
            duplicateAlertMessage = "변경 후 이름이 중복됩니다:\n\n\(preview)\(more)"
            showDuplicateAlert = true
        }
    }

    func applyWithAutoNumbering() {
        print("[RenameVM] applyWithAutoNumbering")
        apply(resolveDuplicates: true)
    }

    func applySkippingDuplicates() {
        let selected = items.filter { $0.isSelected }
        var nameToIndices: [String: [Int]] = [:]
        for (i, item) in selected.enumerated() {
            let name = computePreviewName(item: item, selectedIndex: i)
            nameToIndices[name, default: []].append(i)
        }

        // 중복에 연루된 모든 항목을 선택 해제 (리스트에는 유지)
        var skipIDs = Set<UUID>()
        for (_, indices) in nameToIndices where indices.count > 1 {
            for idx in indices { skipIDs.insert(selected[idx].id) }
        }
        for i in items.indices where skipIDs.contains(items[i].id) {
            items[i].isSelected = false
        }
        print("[RenameVM] applySkippingDuplicates: \(skipIDs.count)개 건너뜀")
        apply(resolveDuplicates: false)
    }

    func apply(resolveDuplicates: Bool = false) {
        let selected = items.filter { $0.isSelected }
        guard !selected.isEmpty else {
            print("[RenameVM] apply: 선택된 항목 없음")
            return
        }
        print("[RenameVM] apply 시작 — 전체 \(items.count)개 중 선택 \(selected.count)개")
        isApplying = true
        errorMessage = nil

        // 샌드박스: 부모 폴더 북마크로 쓰기 접근 시작
        let parentFolders = Set(selected.map { $0.originalURL.deletingLastPathComponent() })
        var accessedBookmarkURLs: [URL] = []
        for parent in parentFolders {
            if let bookmarkedURL = BookmarkManager.shared.restoreURL(for: parent.path) {
                if BookmarkManager.shared.startAccessing(bookmarkedURL) {
                    accessedBookmarkURLs.append(bookmarkedURL)
                    print("[RenameVM] 폴더 접근 시작 (북마크): \(bookmarkedURL.lastPathComponent)")
                } else {
                    print("[RenameVM] 폴더 접근 실패: \(parent.lastPathComponent)")
                }
            } else {
                print("[RenameVM] 북마크 없음: \(parent.lastPathComponent) — 폴더를 선택 버튼으로 다시 열어주세요")
            }
        }
        defer {
            for url in accessedBookmarkURLs { BookmarkManager.shared.stopAccessing(url) }
        }

        let result = renamer.apply(
            items: selected,
            digits: digits,
            startNumber: startNumber,
            unifiedBaseName: unifiedBaseName,
            unifyMode: unifyMode,
            useNumbering: useNumbering,
            resolveDuplicates: resolveDuplicates
        )
        isApplying = false
        if !result.failed.isEmpty {
            let reasons = result.failed.prefix(2).map { "\($0.url.lastPathComponent): \($0.error)" }.joined(separator: ", ")
            errorMessage = "변경 실패 \(result.failed.count)개 — \(reasons)"
            print("[RenameVM] apply 실패 내역: \(result.failed.map { "\($0.url.lastPathComponent): \($0.error)" })")
        }
        let logFolder = folderURL ?? items.first?.originalURL.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())
        if !result.renamed.isEmpty || !result.failed.isEmpty {
            LogWriter.shared.logRenameResult(
                renamed: result.renamed,
                failed: result.failed.map { $0.url },
                folder: logFolder
            )
        }
        // loadFolder는 내부에서 undoStack을 초기화하므로 뷰 갱신 후에 스택에 추가
        if fileMode {
            refreshItemURLs(renamedPairs: result.renamed)
        } else if let folder = folderURL {
            loadFolder(folder)
        }
        if !result.renamed.isEmpty {
            undoStack.append(result.renamed)
        }
        print("[RenameVM] apply 완료 — 성공 \(result.renamed.count)개")
    }

    private func refreshItemURLs(renamedPairs: [(from: URL, to: URL)]) {
        var renamedMap: [URL: URL] = [:]
        for pair in renamedPairs { renamedMap[pair.from] = pair.to }
        items = items.map { item in
            if let newURL = renamedMap[item.originalURL] {
                return RenameItem(originalURL: newURL)
            }
            return item
        }
        // folderURL 갱신 (같은 폴더인 경우)
        let parents = Set(items.map { $0.originalURL.deletingLastPathComponent().path })
        folderURL = parents.count == 1 ? items.first?.originalURL.deletingLastPathComponent() : nil
    }

    func undo() {
        guard let last = undoStack.last else { return }
        let remainingStack = Array(undoStack.dropLast())
        print("[RenameVM] undo: \(last.count)개 되돌리기 시도, 남은 스택 \(remainingStack.count)개")

        // 샌드박스: undo 대상 폴더 접근 시작
        let parentFolders = Set(last.map { $0.to.deletingLastPathComponent() })
        var accessedBookmarkURLs: [URL] = []
        for parent in parentFolders {
            if let bookmarkedURL = BookmarkManager.shared.restoreURL(for: parent.path) {
                if BookmarkManager.shared.startAccessing(bookmarkedURL) {
                    accessedBookmarkURLs.append(bookmarkedURL)
                }
            }
        }
        defer {
            for url in accessedBookmarkURLs { BookmarkManager.shared.stopAccessing(url) }
        }

        var restored: [(from: URL, to: URL)] = []
        var skipped: [URL] = []
        for pair in last.reversed() {
            do {
                try FileManager.default.moveItem(at: pair.to, to: pair.from)
                restored.append((from: pair.to, to: pair.from))
                print("[RenameVM] undo 성공: \(pair.to.lastPathComponent) → \(pair.from.lastPathComponent)")
            } catch {
                skipped.append(pair.to)
                print("[RenameVM] undo 실패: \(pair.to.lastPathComponent) — \(error.localizedDescription)")
            }
        }

        LogWriter.shared.logRenameUndoResult(restored: restored, skipped: skipped)

        // loadFolder는 undoStack을 초기화하므로 갱신 후 남은 스택 복원
        if fileMode {
            var restoredMap: [URL: URL] = [:]
            for pair in last { restoredMap[pair.to] = pair.from }
            items = items.map { item in
                if let oldURL = restoredMap[item.originalURL] {
                    return RenameItem(originalURL: oldURL)
                }
                return item
            }
            let parents = Set(items.map { $0.originalURL.deletingLastPathComponent().path })
            folderURL = parents.count == 1 ? items.first?.originalURL.deletingLastPathComponent() : nil
            undoStack = remainingStack
        } else if let folder = folderURL {
            loadFolder(folder)
            undoStack = remainingStack
        }
    }
}

// MARK: - FileRenameView

struct FileRenameView: View {
    var initialURLs: [URL] = []
    @StateObject private var vm = RenameViewModel()

    var body: some View {
        VStack(spacing: 0) {
            folderHeader
            if vm.folderURL != nil {
                HStack {
                    Text("경로를 클릭하면 Finder에서 열립니다")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
            Divider()
            controlsBar
            Divider()
            columnHeaders
            Divider()
            fileListOrEmpty
            Divider()
            actionBar
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .overlay(dropTargetOverlay)
        .onAppear {
            guard !initialURLs.isEmpty else { return }
            applyInitialURLs(initialURLs)
        }
        .alert("중복 이름 감지", isPresented: $vm.showDuplicateAlert) {
            Button("자동 넘버링") { vm.applyWithAutoNumbering() }
            Button("충돌 파일 건너뜀") { vm.applySkippingDuplicates() }
            Button("취소", role: .cancel) { }
        } message: {
            Text(vm.duplicateAlertMessage)
        }
    }

    // MARK: - Drop target overlay

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if isDropTargeted {
            ZStack {
                Color.accentColor.opacity(0.08)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(6)
                VStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor)
                    Text(vm.items.isEmpty ? "파일 또는 폴더 드롭" : "파일 추가")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
        }
    }

    // MARK: - Folder header

    @State private var isPathHovered = false
    @State private var isDropTargeted = false

    private var folderHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.fileMode ? "doc.on.doc.fill" : "folder.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            if vm.fileMode {
                if let url = vm.folderURL {
                    Text("\(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))  ·  \(vm.fileModeCount)개 파일")
                        .font(.system(size: 11))
                        .foregroundColor(isPathHovered ? .accentColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture { NSWorkspace.shared.open(url) }
                        .onHover { isPathHovered = $0 }
                        .help("Finder에서 열기")
                } else {
                    Text("\(vm.fileModeCount)개 파일 선택됨 (여러 폴더)")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                }
            } else if let url = vm.folderURL {
                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11))
                    .foregroundColor(isPathHovered ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .onHover { isPathHovered = $0 }
                    .help("Finder에서 열기")
            } else {
                Text("폴더 또는 파일을 여기에 드롭하거나 폴더를 선택하세요")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if vm.folderURL != nil {
                Button {
                    vm.clearFolder()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("폴더 제거")
            }
            Button("폴더 선택") { selectFolder() }
                .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Controls bar

    private var controlsBar: some View {
        HStack(alignment: .top, spacing: 0) {

            // 번호 자릿수
            VStack(alignment: .leading, spacing: 4) {
                Text("번호 자릿수")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Picker("", selection: $vm.digits) {
                    ForEach(1 ... 5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .labelsHidden()
                .disabled(!vm.useNumbering)
                .opacity(vm.useNumbering ? 1 : 0.4)
            }
            .padding(.horizontal, 14)

            Divider().frame(height: 46)

            // 시작 번호
            VStack(alignment: .leading, spacing: 4) {
                Text("시작 번호")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("없음", text: $vm.startNumberText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .font(.system(size: 11))
                    .onChange(of: vm.startNumberText) { val in
                        let filtered = val.filter { $0.isNumber }
                        if filtered != val { vm.startNumberText = filtered }
                    }
                Text("비우면 번호 없이 저장")
                    .font(.system(size: 9))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 14)

            Divider().frame(height: 46)

            // 공통 이름
            VStack(alignment: .leading, spacing: 4) {
                Text("공통 이름")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("비워두면 원본 유지", text: $vm.unifiedBaseName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .font(.system(size: 11))
                Text("비우면 원본 파일명 유지")
                    .font(.system(size: 9))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 14)

            Divider().frame(height: 46)

            // 통일 방식
            VStack(alignment: .leading, spacing: 4) {
                Text("통일 방식")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Picker("", selection: $vm.unifyMode) {
                    Text("통일명").tag(0)
                    Text("통일명(원본명)").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .labelsHidden()
                Text(vm.unifyMode == 0 ? "번호_통일명.확장자" : "번호_통일명(원본명).확장자")
                    .font(.system(size: 9))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 14)

            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Column headers

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            // 전체 선택 체크박스
            Button {
                vm.toggleSelectAll()
            } label: {
                Image(systemName: vm.allSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(vm.allSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 14)

            // 드래그 핸들 자리
            Spacer().frame(width: 14)

            Text("원본 파일명")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 화살표 자리 (투명, 정렬용)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(.clear)

            Text("변경 후 미리보기")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // × 버튼 자리 (정렬용)
            Spacer().frame(width: 16)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }

    // MARK: - File list / empty state

    @ViewBuilder
    private var fileListOrEmpty: some View {
        if vm.items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 36))
                    .foregroundColor(Color.secondary.opacity(0.25))
                Text("폴더를 선택하면 파일 목록이 표시됩니다")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach($vm.items) { $item in
                    let idx = vm.items.firstIndex(where: { $0.id == item.id }) ?? 0
                    RenameRowView(
                        item: $item,
                        preview: vm.previewName(for: item, at: idx),
                        onRemove: { vm.removeItem(id: item.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                }
                .onMove(perform: vm.moveItems)
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
            Spacer()
            Button("목록에서 제거") { vm.removeSelectedItems() }
                .buttonStyle(ActionButtonStyle(color: Color(NSColor.systemRed)))
                .disabled(vm.items.filter { $0.isSelected }.isEmpty)

            Button {
                vm.undo()
            } label: {
                Text("↩ 되돌리기 (\(vm.undoCount))")
            }
            .buttonStyle(ActionButtonStyle(color: vm.canUndo ? Color(NSColor.systemOrange) : Color(NSColor.systemGray)))
            .disabled(!vm.canUndo)

            Button("초기화") { vm.reset() }
                .buttonStyle(ActionButtonStyle(color: Color(NSColor.systemGray)))
                .disabled(vm.items.isEmpty)

            Button {
                vm.checkAndApply()
            } label: {
                if vm.isApplying {
                    ProgressView().controlSize(.mini).padding(.horizontal, 6)
                } else {
                    Text("적용")
                }
            }
            .buttonStyle(ActionButtonStyle(color: Color(NSColor.systemBlue)))
            .disabled(vm.items.isEmpty || vm.isApplying)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Folder actions

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            vm.loadFolder(url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        print("[FileRenameView] handleDrop: \(providers.count)개 provider")
        var collectedURLs: [URL?] = Array(repeating: nil, count: providers.count)
        let group = DispatchGroup()
        for (i, provider) in providers.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                defer { group.leave() }
                if let error { print("[FileRenameView] provider[\(i)] 오류: \(error)"); return }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    print("[FileRenameView] provider[\(i)] URL 파싱 실패")
                    return
                }
                print("[FileRenameView] provider[\(i)]: \(url.lastPathComponent)")
                collectedURLs[i] = url
            }
        }
        group.notify(queue: .main) {
            let urls = collectedURLs.compactMap { $0 }
            guard !urls.isEmpty else {
                print("[FileRenameView] handleDrop: 수집된 URL 없음")
                return
            }
            print("[FileRenameView] handleDrop: 수집 완료 \(urls.count)개, 현재 목록 \(self.vm.items.count)개")
            // 기존 목록이 있으면 추가, 없으면 새로 로드
            if self.vm.items.isEmpty {
                self.applyInitialURLs(urls)
            } else {
                self.vm.appendURLs(urls)
            }
        }
        return true
    }

    private func applyInitialURLs(_ urls: [URL]) {
        var isDir: ObjCBool = false
        let isDirectory: (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        // 단일 폴더
        if urls.count == 1 && isDirectory(urls[0]) {
            vm.loadFolder(urls[0])
            return
        }

        // 다중 폴더: 각 폴더의 파일 수집
        let folders = urls.filter { isDirectory($0) }
        if !folders.isEmpty {
            var allFiles: [URL] = []
            for folder in folders {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                allFiles += contents.filter {
                    (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                }
            }
            if !allFiles.isEmpty { vm.loadFiles(allFiles) }
            return
        }

        // 파일만
        let files = urls.filter { !isDirectory($0) }
        if !files.isEmpty { vm.loadFiles(files) }
    }
}
