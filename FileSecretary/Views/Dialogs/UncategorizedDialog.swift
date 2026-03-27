import SwiftUI

struct UncategorizedDialog: View {
    let fileName: String
    let mainFolderName: String?
    let onMoveToMain: (Bool) -> Void
    let onLeaveInPlace: (Bool) -> Void
    let onMoveToLocalEtc: (Bool) -> Void

    @State private var applyToAll = false

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

            VStack(spacing: 8) {
                if let name = mainFolderName {
                    Button(action: { onMoveToMain(applyToAll) }) {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                            Text("메인 폴더로 이동")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(name)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .keyboardShortcut(.defaultAction)
                }

                Button(action: { onMoveToLocalEtc(applyToAll) }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("해당 폴더에 기타 폴더 만들어서 이동")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(mainFolderName == nil ? .defaultAction : KeyboardShortcut("e", modifiers: .command))

                Button(action: { onLeaveInPlace(applyToAll) }) {
                    HStack {
                        Image(systemName: "minus.circle")
                        Text("해당 폴더에 남기기 (건너뜀)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            Toggle(isOn: $applyToAll) {
                Text("이 대상 폴더의 이후 미분류 파일에 모두 적용")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .toggleStyle(.checkbox)
        }
        .padding(20)
        .frame(width: 380)
    }
}
