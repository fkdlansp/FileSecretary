import SwiftUI
import UniformTypeIdentifiers

struct LeftPanelView: View {
    @ObservedObject var vm: OrganizerViewModel

    @State private var isTargetDropTargeted = false
    @State private var isOutputDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: 대상 폴더 드롭존
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader("대상 폴더")

                    ForEach(Array(vm.targetFolders.enumerated()), id: \.offset) { idx, url in
                        FolderRow(
                            label: String(format: "%02d", idx + 1),
                            url: url,
                            tooltip: "제외"
                        ) {
                            vm.removeTargetFolder(at: IndexSet(integer: idx))
                        }
                    }

                    AddFolderButton(label: "+ 폴더 추가 / 드롭") {
                        vm.openFolderPanel { vm.addTargetFolder($0) }
                    }

                    if isTargetDropTargeted {
                        Text("여기에 놓으면 대상 폴더로 추가됩니다")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isTargetDropTargeted ? Color.accentColor.opacity(0.07) : Color.clear)
                        .padding(4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isTargetDropTargeted ? Color.accentColor.opacity(0.45) : Color.clear,
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .padding(4)
                )
                .animation(.easeInOut(duration: 0.15), value: isTargetDropTargeted)
                .onDrop(of: [UTType.fileURL], isTargeted: $isTargetDropTargeted) { providers in
                    handleDrop(providers, to: .target)
                    return true
                }

                Divider().padding(.vertical, 8)

                // MARK: 출력 폴더 드롭존
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader("출력 폴더 (최대 4개)")

                    ForEach(Array(vm.outputFolders.enumerated()), id: \.offset) { idx, url in
                        OutputFolderRow(idx: idx, url: url) {
                            vm.removeOutputFolder(at: IndexSet(integer: idx))
                        }
                    }

                    AddFolderButton(
                        label: "+ 폴더 추가 / 드롭",
                        disabled: vm.outputFolders.count >= 4
                    ) {
                        vm.openFolderPanel { vm.addOutputFolder($0) }
                    }

                    if isOutputDropTargeted {
                        Text("여기에 놓으면 출력 폴더로 추가됩니다")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    } else if vm.outputFolders.isEmpty {
                        Text("미지정된 파일은 각 대상 폴더 안에서 분류됩니다.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                    } else {
                        Text("미지정된 파일은 메인 폴더의 기타 폴더로 이동됩니다.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOutputDropTargeted ? Color.green.opacity(0.07) : Color.clear)
                        .padding(4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isOutputDropTargeted ? Color.green.opacity(0.45) : Color.clear,
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .padding(4)
                )
                .animation(.easeInOut(duration: 0.15), value: isOutputDropTargeted)
                .onDrop(of: [UTType.fileURL], isTargeted: $isOutputDropTargeted) { providers in
                    guard vm.outputFolders.count < 4 else { return false }
                    handleDrop(providers, to: .output)
                    return true
                }

                Divider().padding(.vertical, 8)

                // MARK: 원 클릭 다운로드 정리
                SectionHeader("원 클릭 다운로드 폴더 정리")
                Text("~/Downloads  •  파일 타입 기준  •  넘버링 없음")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                Button {
                    vm.organizeDownloads()
                } label: {
                    if vm.isOrganizing {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text("정리 중...")
                        }
                    } else {
                        Text("지금 정리")
                    }
                }
                .buttonStyle(SmallButtonStyle(color: .accentColor))
                .disabled(vm.isOrganizing)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider().padding(.vertical, 8)

                // MARK: 도구
                SectionHeader("도구")

                HStack(spacing: 8) {
                    Button("프리셋 저장") { vm.savePreset() }
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.5))
                    Button("불러오기") { vm.loadPreset() }
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondary.opacity(0.5))
                    Button("로그 폴더") { vm.openLogFolder() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)


            }
        }
        .frame(width: 210)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Drop handling

    private enum DropDest { case target, output }

    private func handleDrop(_ providers: [NSItemProvider], to dest: DropDest) {
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            switch dest {
            case .target: urls.forEach { vm.addTargetFolder($0) }
            case .output: urls.forEach { vm.addOutputFolder($0) }
            }
        }
    }
}

// MARK: - Subviews

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

private struct FolderRow: View {
    let label: String
    let url: URL
    let tooltip: String
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .trailing)

            Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .opacity(isHovered ? 1 : 0.6)
            }
            .buttonStyle(.plain)
            .help(tooltip)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .onHover { isHovered = $0 }
    }
}

private struct OutputFolderRow: View {
    let idx: Int
    let url: URL
    let onRemove: () -> Void

    private let colors: [Color] = [.blue, .green, .orange, .purple]
    private let labels = ["A","B","C","D"]

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colors[safe: idx] ?? .gray)
                .frame(width: 8, height: 8)

            Text(labels[safe: idx] ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if idx == 0 {
                Text("메인")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(3)
            }

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("제외")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

private struct AddFolderButton: View {
    let label: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(disabled ? .secondary : .accentColor)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct SmallButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(.white)
            .cornerRadius(6)
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
