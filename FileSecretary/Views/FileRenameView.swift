import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - RenameViewModel

private class RenameViewModel: ObservableObject {

    @Published var folderURL: URL? = nil
    @Published var items: [RenameItem] = []
    @Published var digits: Int = 3
    @Published var startNumber: Int = 1
    @Published var unifyBase: Bool = false
    @Published var unifiedBaseName: String = ""
    @Published var isApplying: Bool = false
    @Published var errorMessage: String? = nil

    private let renamer = FileRenamer()
    private var snapshot: [RenameItem] = []

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
        let numStr = String(format: "%0\(digits)d", startNumber + index)
        let trimmed = unifiedBaseName.trimmingCharacters(in: .whitespaces)
        let base = (unifyBase && !trimmed.isEmpty) ? trimmed : item.baseName
        let ext  = item.ext.isEmpty ? "" : ".\(item.ext)"
        return "\(numStr)_\(base)\(ext)"
    }

    // MARK: Actions

    func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func reset() {
        items = snapshot
        digits = 3
        startNumber = 1
        unifyBase = false
        unifiedBaseName = ""
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
            unifyBase: unifyBase,
            unifiedBaseName: unifiedBaseName
        )
        isApplying = false
        if !result.failed.isEmpty {
            errorMessage = "변경 실패 \(result.failed.count)개"
        }
        loadFolder(folder)
    }
}

// MARK: - FileRenameView

struct FileRenameView: View {
    @StateObject private var vm = RenameViewModel()

    var body: some View {
        VStack(spacing: 0) {
            folderHeader
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
    }

    // MARK: - Folder header

    private var folderHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            Text(vm.folderURL?.path ?? "폴더를 여기에 드롭하거나 선택하세요")
                .font(.system(size: 11))
                .foregroundColor(vm.folderURL == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("폴더 선택") { selectFolder() }
                .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Controls bar

    private var controlsBar: some View {
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

            Divider().frame(height: 18)

            Text("시작 번호")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("", text: Binding(
                get: { String(vm.startNumber) },
                set: { if let n = Int($0), n > 0 { vm.startNumber = n } }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 54)
            .font(.system(size: 11))

            Divider().frame(height: 18)

            Toggle("파일명 통일", isOn: $vm.unifyBase)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            if vm.unifyBase {
                TextField("공통 이름", text: $vm.unifiedBaseName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 140)
            }

            Spacer()
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
            Button("초기화") { vm.reset() }
                .buttonStyle(ActionButtonStyle(color: Color(NSColor.systemOrange)))
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
