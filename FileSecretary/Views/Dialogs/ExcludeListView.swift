import SwiftUI

struct ExcludeListView: View {
    @Binding var excludeList: ExcludeList
    @Environment(\.dismiss) private var dismiss

    @State private var keywordInput   = ""
    @State private var extensionInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("제외 목록 편집")
                .font(.system(size: 14, weight: .semibold))

            // Keywords
            sectionHeader("키워드 (파일명에 포함 시 제외)")
            tagList(items: excludeList.keywords) { kw in
                excludeList.keywords.removeAll { $0 == kw }
            }
            addRow(placeholder: "키워드 입력 후 Return", text: $keywordInput, onAdd: addKeyword)

            Divider()

            // Extensions
            sectionHeader("확장자 (예: .DS_Store, .tmp)")
            tagList(items: excludeList.extensions) { ext in
                excludeList.extensions.removeAll { $0 == ext }
            }
            addRow(placeholder: ".확장자 입력 후 Return", text: $extensionInput, onAdd: addExtension)

            Divider()

            HStack {
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .frame(minHeight: 260)
    }

    // MARK: - Subviews

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium))
    }

    private func tagList(items: [String], onRemove: @escaping (String) -> Void) -> some View {
        Group {
            if items.isEmpty {
                Text("없음")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 4) {
                            Text(item)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Button { onRemove(item) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func addRow(placeholder: String, text: Binding<String>, onAdd: @escaping () -> Void) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit { onAdd() }
            Button("추가") { onAdd() }
                .font(.system(size: 11))
        }
    }

    // MARK: - Actions

    private func addKeyword() {
        let kw = keywordInput.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !excludeList.keywords.contains(kw) else { return }
        excludeList.keywords.append(kw)
        keywordInput = ""
    }

    private func addExtension() {
        var ext = extensionInput.trimmingCharacters(in: .whitespaces)
        guard !ext.isEmpty else { return }
        if !ext.hasPrefix(".") { ext = "." + ext }
        guard !excludeList.extensions.contains(ext) else {
            extensionInput = ""
            return
        }
        excludeList.extensions.append(ext)
        extensionInput = ""
    }
}
