import SwiftUI

struct CategoryConflictDialog: View {
    let fileName: String
    let categories: [Category]
    let onSelect: (Category, Bool) -> Void
    let onSkip: (Bool) -> Void

    @State private var selectedId: String = ""
    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                Text("카테고리 중복")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text("아래 파일이 여러 카테고리에 동시에 해당합니다. 이동할 카테고리를 선택하세요.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(fileName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(5)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(categories) { cat in
                    Button {
                        selectedId = cat.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedId == cat.id ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(selectedId == cat.id ? .accentColor : .secondary)
                                .font(.system(size: 14))
                            Text(cat.folderName)
                                .font(.system(size: 11))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Toggle(isOn: $applyToAll) {
                Text("같은 카테고리 조합의 이후 파일에 모두 적용")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("건너뛰기") { onSkip(applyToAll) }
                    .keyboardShortcut(.cancelAction)
                Button("이동") {
                    if let cat = categories.first(where: { $0.id == selectedId }) {
                        onSelect(cat, applyToAll)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedId.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            selectedId = categories.first?.id ?? ""
        }
    }
}
