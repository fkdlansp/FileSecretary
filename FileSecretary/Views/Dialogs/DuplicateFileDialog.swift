import SwiftUI

struct DuplicateFileDialog: View {
    let fileName: String
    @State private var selected: DuplicateMode = .addNumber
    let onConfirm: (DuplicateMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("중복 파일 처리 방식")
                .font(.system(size: 13, weight: .semibold))

            // Show the conflicting filename
            if !fileName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(fileName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }

            Text("이동 대상 위치에 동일한 이름의 파일이 이미 있습니다. 어떻게 처리할까요?")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                OptionRow(
                    mode: .addNumber,
                    selected: $selected,
                    title: "번호 추가 (기본값)",
                    example: "사진.jpg → 사진 2.jpg"
                )
                OptionRow(
                    mode: .overwrite,
                    selected: $selected,
                    title: "덮어쓰기",
                    example: "기존 파일을 교체합니다"
                )
                OptionRow(
                    mode: .skip,
                    selected: $selected,
                    title: "건너뛰기",
                    example: "이 파일은 이동하지 않습니다"
                )
            }

            Divider()

            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("확인") { onConfirm(selected) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct OptionRow: View {
    let mode: DuplicateMode
    @Binding var selected: DuplicateMode
    let title: String
    let example: String

    var body: some View {
        Button {
            selected = mode
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected == mode ? .accentColor : .secondary)
                    .font(.system(size: 14))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 11, weight: .medium))
                    Text(example).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
