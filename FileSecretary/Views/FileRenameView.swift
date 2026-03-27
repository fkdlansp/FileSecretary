import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - RenameViewModel

private class RenameViewModel: ObservableObject {

    @Published var folderURL: URL? = nil
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
    }

    // MARK: Preview

    func previewName(for item: RenameItem, at index: Int) -> String {
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
            let numStr = String(format: "%0\(digits)d", startNumber + index)
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
        folderURL = nil
        items = []
        snapshot = []
        undoStack = []
        errorMessage = nil
    }

    func apply() {
        guard !items.isEmpty, let folder = folderURL else { return }
        isApplying = true
        errorMessage = nil
        let result = renamer.apply(
            items: items,
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
        loadFolder(folder)
    }

    func undo() {
        guard let last = undoStack.last, let folder = folderURL else { return }
        for pair in last.reversed() {
            try? FileManager.default.moveItem(at: pair.to, to: pair.from)
        }
        undoStack.removeLast()
        loadFolder(folder)
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
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            if let url = vm.folderURL {
                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11))
                    .foregroundColor(isPathHovered ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .onHover { isPathHovered = $0 }
                    .help("Finder에서 열기")
            } else {
                Text("폴더를 여기에 드롭하거나 선택하세요")
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
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: 번호 자릿수, 시작 번호, 공통 이름, 통일 방식
            HStack(spacing: 12) {
                Text("번호 자릿수")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Picker("", selection: $vm.digits) {
                    ForEach(1 ... 5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .labelsHidden()
                .disabled(!vm.useNumbering)
                .opacity(vm.useNumbering ? 1 : 0.4)

                Divider().frame(height: 18)

                Text("시작 번호")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("없음", text: $vm.startNumberText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 54)
                    .font(.system(size: 11))
                    .onChange(of: vm.startNumberText) { val in
                        let filtered = val.filter { $0.isNumber }
                        if filtered != val { vm.startNumberText = filtered }
                    }

                Divider().frame(height: 18)

                Text("공통 이름")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("비우면 원본 파일명 유지", text: $vm.unifiedBaseName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 160)

                Divider().frame(height: 18)

                Text("통일 방식")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Picker("", selection: $vm.unifyMode) {
                    Text("통일명").tag(0)
                    Text("통일명(원본명)").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .labelsHidden()

                Spacer()
            }

            // 안내
            Text("시작 번호를 비워두면 번호 없이 저장됩니다  ·  공통 이름을 비워두면 원본 파일명이 유지됩니다")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Column headers

    private var columnHeaders: some View {
        HStack {
            Spacer().frame(width: 22)
            Text("원본 파일명")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text("변경 후 미리보기")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Spacer().frame(width: 8)
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
        guard let provider = providers.first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            DispatchQueue.main.async { vm.loadFolder(url) }
        }
        return true
    }
}
