import SwiftUI

struct CategoryConflictDialog: View {
    let fileName: String
    let categories: [Category]
    let onSelect: (Category) -> Void
    let onSkip: () -> Void

    @State private var selectedId: String = ""

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

            HStack {
                Spacer()
                Button("이 파일만 건너뛰기", action: onSkip)
                    .keyboardShortcut(.cancelAction)
                Button("이동") {
                    if let cat = categories.first(where: { $0.id == selectedId }) {
                        onSelect(cat)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedId.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            selectedId = categories.first?.id ?? ""
        }
    }
}
