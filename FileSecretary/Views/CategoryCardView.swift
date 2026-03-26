import SwiftUI

struct CategoryCardView: View {
    let category: Category
    let outputFolders: [URL]
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onOutputChange: (Int) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                // Number + Name
                Text(String(format: "%02d", category.num))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                Text(category.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                // Condition badge
                ConditionBadge(category: category)

                Spacer()

                // Edit / Remove
                HStack(spacing: 4) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("수정")

                    Button(action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("제외")
                }
                .opacity(isHovered ? 1 : 0.5)
            }

            // Condition tags + output dropdown
            HStack(spacing: 6) {
                // Indent to align with name
                Spacer().frame(width: 44)

                ConditionTagsView(category: category)

                Spacer()

                // Output dropdown
                OutputDropdown(
                    selectedIdx: category.outputIdx,
                    outputFolders: outputFolders,
                    onChange: onOutputChange
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - ConditionBadge

private struct ConditionBadge: View {
    let category: Category

    var label: String {
        switch category.conditionType {
        case .keyword: return "키워드"
        case .type:    return "타입"
        case .both:
            let logic = category.logic == .or ? "OR" : "AND"
            return "키워드+타입 \(logic)"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundColor(.accentColor)
            .cornerRadius(4)
    }
}

// MARK: - ConditionTagsView

private struct ConditionTagsView: View {
    let category: Category

    var body: some View {
        HStack(spacing: 4) {
            if !category.keywords.isEmpty {
                Text("키워드: \(category.keywords.joined(separator: ", "))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if !category.types.isEmpty {
                Text("타입: \(category.types.joined(separator: ", "))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - OutputDropdown

private struct OutputDropdown: View {
    let selectedIdx: Int
    let outputFolders: [URL]
    let onChange: (Int) -> Void

    private let labels = ["A","B","C","D"]

    var selectedLabel: String {
        if selectedIdx == 0 || outputFolders.isEmpty { return "개별 모드" }
        let folderIdx = selectedIdx - 1
        guard folderIdx < outputFolders.count else { return "개별 모드" }
        return "\(labels[folderIdx]): \(outputFolders[folderIdx].lastPathComponent)"
    }

    var body: some View {
        Menu(selectedLabel) {
            Button("개별 모드") { onChange(0) }
            Divider()
            ForEach(Array(outputFolders.enumerated()), id: \.offset) { i, url in
                Button("\(labels[safe: i] ?? ""): \(url.lastPathComponent)\(i == 0 ? " (메인)" : "")") {
                    onChange(i + 1)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .font(.system(size: 10))
        .frame(maxWidth: 130)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
