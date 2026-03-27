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

    private let renamer = FileRenamer()
    private var snapshot: [RenameItem] = []
    private var undoStack: [[(from: URL, to: URL)]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var undoCount: Int { undoStack.count }

    // MARK: Folder loading

    func loadFolder(_ url: URL) {
        fileMode = false
        folderURL = url
        errorMessage = nil
        let all = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let regular = all
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        items = regular.map { RenameItem(originalURL: $0) }
        snapshot = items
        undoStack = []
    }

    // MARK: File loading (개별 파일 드래그)

    func loadFiles(_ urls: [URL]) {
        fileMode = true
        errorMessage = nil
        let regular = urls
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        items = regular.map { RenameItem(originalURL: $0) }
        snapshot = items
        fileModeCount = items.count
        undoStack = []
        // 모든 파일이 같은 폴더면 folderURL 표시용으로만 사용
        let parents = Set(regular.map { $0.deletingLastPathComponent().path })
        folderURL = parents.count == 1 ? regular.first?.deletingLastPathComponent() : nil
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

    func apply() {
        guard !items.isEmpty else { return }
        isApplying = true
        errorMessage = nil
        let result = renamer.apply(
            items: items.filter { $0.isSelected },
            digits: digits,
            startNumber: startNumber,
            unifiedBaseName: unifiedBaseName,
            unifyMode: unifyMode,
            useNumbering: useNumbering
        )
        isApplying = false
        if !result.renamed.isEmpty {
            undoStack.append(result.renamed)
        }
        if !result.failed.isEmpty {
            errorMessage = "변경 실패 \(result.failed.count)개"
        }
        let logFolder = folderURL ?? items.first?.originalURL.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())
        if !result.renamed.isEmpty || !result.failed.isEmpty {
            LogWriter.shared.logRenameResult(renamed: result.renamed, failed: result.failed, folder: logFolder)
        }
        if fileMode {
            refreshItemURLs(renamedPairs: result.renamed)
        } else if let folder = folderURL {
            loadFolder(folder)
        }
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
        for pair in last.reversed() {
            try? FileManager.default.moveItem(at: pair.to, to: pair.from)
        }
        undoStack.removeLast()
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
        } else if let folder = folderURL {
            loadFolder(folder)
        }
    }
}

// MARK: - FileRenameView

struct FileRenameView: View {
    var initialFolderURL: URL? = nil
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
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onAppear {
            if let url = initialFolderURL {
                vm.loadFolder(url)
            }
        }
    }

    // MARK: - Folder header

    @State private var isPathHovered = false

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
                        preview: vm.previewName(for: item, at: idx)
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
                vm.apply()
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
        var collectedURLs: [URL?] = Array(repeating: nil, count: providers.count)
        let group = DispatchGroup()
        for (i, provider) in providers.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                collectedURLs[i] = url
            }
        }
        group.notify(queue: .main) {
            let urls = collectedURLs.compactMap { $0 }
            guard !urls.isEmpty else { return }
            // 단일 폴더 드래그
            if urls.count == 1 {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &isDir), isDir.boolValue {
                    vm.loadFolder(urls[0])
                    return
                }
            }
            // 파일만 필터링
            let files = urls.filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
            }
            if !files.isEmpty { vm.loadFiles(files) }
        }
        return true
    }
}
