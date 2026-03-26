import SwiftUI

struct UncategorizedDialog: View {
    let fileName: String
    let onMoveToEtc: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                Text("분류되지 않은 파일")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text("아래 파일이 어떤 카테고리에도 해당하지 않습니다.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(fileName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(5)

            Divider()

            HStack {
                Spacer()
                Button("건너뛰기", action: onSkip)
                    .keyboardShortcut(.cancelAction)
                Button("기타로 이동", action: onMoveToEtc)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
