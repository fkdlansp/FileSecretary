import SwiftUI

struct RenameRowView: View {
    @Binding var item: RenameItem
    let preview: String

    @State private var isEditing = false
    @State private var editBuffer = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // 체크박스
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
                .frame(width: 14)

            // 드래그 핸들
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundColor(Color.secondary.opacity(0.45))
                .frame(width: 14)

            // 원본 파일명 (더블클릭 편집)
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
                        .foregroundColor(item.isSelected ? .primary : .secondary)
                        .help("더블 클릭으로 파일 기본명 편집")
                        .onTapGesture(count: 2) { startEdit() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 가운데 화살표
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(Color.secondary.opacity(0.4))

            // 변경 후 미리보기
            Text(preview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(item.isSelected ? .secondary : Color.secondary.opacity(0.35))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
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
