import SwiftUI

@main
struct FileSecretaryApp: App {
    var body: some Scene {
        WindowGroup("File Secretary") {
            ContentView()
        }
        .defaultSize(width: 260, height: 220)
        .commands {
            PresetCommands()
            SettingsCommands()
        }
    }
}

// MARK: - Commands
// OrganizerViewModel.current is set on init() and lives for the app's lifetime.
// Using a static reference bypasses SwiftUI's unreliable focus mechanism for commands.

struct PresetCommands: Commands {
    var body: some Commands {
        CommandMenu("프리셋") {
            Button("프리셋 저장") { OrganizerViewModel.current?.savePreset() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("프리셋 불러오기") { OrganizerViewModel.current?.loadPreset() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}

struct SettingsCommands: Commands {
    var body: some Commands {
        CommandMenu("환경설정") {
            Button("제외 목록 편집...") { OrganizerViewModel.current?.showExcludeListEditor = true }
            Button("로그 파일 열기") { OrganizerViewModel.current?.openLogFolder() }
            Divider()
            Button("기본값으로 초기화") { OrganizerViewModel.current?.resetToDefaults() }
        }
    }
}
