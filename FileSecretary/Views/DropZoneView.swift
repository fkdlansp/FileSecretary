import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropZoneView: View {
    let tab: AppTab
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    private var hintText: String {
        tab == .organizer
            ? "폴더를 드롭하거나 선택하세요"
            : "파일 또는 폴더를 드롭하거나 선택하세요"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                )
                .padding(14)

            VStack(spacing: 10) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 30))
                    .foregroundColor(isTargeted ? .accentColor : Color.secondary.opacity(0.6))

                Text(hintText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("폴더 선택") {
                    openPanel()
                }
                .buttonStyle(SelectButtonStyle())
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            loadURLs(from: providers)
            return true
        }
    }

    // MARK: - Panel

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = tab == .rename
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "선택"
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            onDrop(urls)
        }
    }

    // MARK: - Drop loading

    private func loadURLs(from providers: [NSItemProvider]) {
        var result: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                guard exists else { return }

                if tab == .rename || isDir.boolValue {
                    result.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            guard !result.isEmpty else { return }
            onDrop(result)
        }
    }
}

// MARK: - Button style

private struct SelectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(configuration.isPressed
                                  ? Color.accentColor.opacity(0.08)
                                  : Color.clear)
                    )
            )
    }
}
