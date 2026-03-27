import SwiftUI
import AppKit

enum AppTab: String, CaseIterable {
    case organizer = "파일 정리"
    case rename = "파일명 편집"
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .organizer
    @State private var isExpanded = false
    @State private var targetFolders: [URL] = []
    @State private var renameFolderURL: URL? = nil
    @StateObject private var organizerVM = OrganizerViewModel()

    var body: some View {
        Group {
            if isExpanded {
                ExpandedRootView(
                    selectedTab: $selectedTab,
                    targetFolders: $targetFolders,
                    renameFolderURL: renameFolderURL,
                    organizerVM: organizerVM
                )
            } else {
                CompactRootView(
                    selectedTab: $selectedTab,
                    isExpanded: $isExpanded,
                    targetFolders: $targetFolders,
                    renameFolderURL: $renameFolderURL
                )
            }
        }
        .background(
            WindowFinder { window in
                configureWindow(window, expanded: isExpanded)
            }
        )
        .onChange(of: isExpanded) { expanded in
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                animateWindow(window, toExpanded: expanded)
            }
        }
    }

    private func configureWindow(_ window: NSWindow, expanded: Bool) {
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.styleMask.remove(.resizable)
        if !expanded {
            let size = NSSize(width: 260, height: 220)
            window.setContentSize(size)
            window.minSize = size
            window.maxSize = size
        }
    }

    private func animateWindow(_ window: NSWindow, toExpanded: Bool) {
        let targetSize: NSSize
        if toExpanded {
            targetSize = NSSize(width: 820, height: 640)
        } else {
            targetSize = NSSize(width: 260, height: 220)
        }

        let currentFrame = window.frame
        let newOriginY = currentFrame.origin.y + currentFrame.height - targetSize.height
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newOriginY,
            width: targetSize.width,
            height: targetSize.height
        )

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        } completionHandler: {
            window.styleMask.remove(.resizable)
            window.minSize = targetSize
            window.maxSize = targetSize
        }
    }
}

// MARK: - State A: Compact

struct CompactRootView: View {
    @Binding var selectedTab: AppTab
    @Binding var isExpanded: Bool
    @Binding var targetFolders: [URL]
    @Binding var renameFolderURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(selectedTab: $selectedTab, compact: true)
            Divider()
            DropZoneView(tab: selectedTab) { urls in
                if selectedTab == .rename {
                    renameFolderURL = urls.first(where: {
                        var isDir: ObjCBool = false
                        return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue
                    }) ?? urls.first.map { $0.deletingLastPathComponent() }
                } else {
                    targetFolders = urls
                }
                isExpanded = true
            }
        }
        .frame(width: 260, height: 220)
    }
}

// MARK: - State B: Expanded

struct ExpandedRootView: View {
    @Binding var selectedTab: AppTab
    @Binding var targetFolders: [URL]
    let renameFolderURL: URL?
    let organizerVM: OrganizerViewModel

    var body: some View {
        VStack(spacing: 0) {
            DiskStatusBar()

            TabBarView(selectedTab: $selectedTab, compact: false)

            Divider()

            Group {
                switch selectedTab {
                case .organizer:
                    FileOrganizerView(targetFolders: $targetFolders, vm: organizerVM)
                case .rename:
                    FileRenameView(initialFolderURL: renameFolderURL)
                }
            }
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 640)
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    @Binding var selectedTab: AppTab
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabButton(
                    title: tab.rawValue,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 6 : 4)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window Finder

private struct WindowFinder: NSViewRepresentable {
    let onFound: (NSWindow) -> Void

    func makeCoordinator() -> ResizeLockCoordinator { ResizeLockCoordinator() }

    func makeNSView(context: Context) -> CapturingView {
        let v = CapturingView()
        v.onFound = { window in
            context.coordinator.install(on: window)
            self.onFound(window)
        }
        return v
    }

    func updateNSView(_ nsView: CapturingView, context: Context) {
        if let w = nsView.window { onFound(w) }
    }

    class CapturingView: NSView {
        var onFound: (NSWindow) -> Void = { _ in }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let w = window { onFound(w) }
        }
    }
}

// MARK: - Resize Lock Delegate

/// windowWillResize(_:to:)는 사용자 드래그에만 호출됨.
/// 프로그래밍적 setFrame(애니메이션)은 거치지 않아 전환 애니메이션에 영향 없음.
private final class ResizeLockCoordinator: NSObject, NSWindowDelegate {
    private weak var previousDelegate: NSWindowDelegate?
    private var installed = false

    func install(on window: NSWindow) {
        guard !installed else { return }
        installed = true
        previousDelegate = window.delegate
        window.delegate = self
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        return sender.frame.size  // 현재 크기 반환 → 드래그 리사이즈 차단
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (previousDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        previousDelegate?.responds(to: aSelector) == true ? previousDelegate : super.forwardingTarget(for: aSelector)
    }
}
