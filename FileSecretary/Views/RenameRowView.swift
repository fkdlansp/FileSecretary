import SwiftUI

struct RenameRowView: View {
    @Binding var item: RenameItem
    let preview: String

    @State private var isEditing = false
    @State private var editBuffer = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Drag handle indicator
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundColor(Color.secondary.opacity(0.45))
                .frame(width: 14)

            // Original name (editable on double-click)
            Group {
                if isEditing {
                    TextField("", text: $editBuffer)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .focused($fieldFocused)
                        .onSubmit { commit() }
                        .onExitCommand { cancel() }
                        .onAppear { fieldFocused = true }
                } else {
                    Text(item.displayName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .help("더블 클릭으로 파일 기본명 편집")
                        .onTapGesture(count: 2) { startEdit() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(Color.secondary.opacity(0.4))

            // Preview
            Text(preview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(minWidth: 170, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    // MARK: - Inline edit actions

    private func startEdit() {
        editBuffer = item.baseName
        isEditing = true
    }

    private func commit() {
        let t = editBuffer.trimmingCharacters(in: .whitespaces)
        item.customName = t.isEmpty ? nil : t
        isEditing = false
    }

    private func cancel() {
        isEditing = false
    }
}
