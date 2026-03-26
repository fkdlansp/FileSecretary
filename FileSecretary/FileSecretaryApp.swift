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

struct PresetCommands: Commands {
    @FocusedObject private var vm: OrganizerViewModel?

    var body: some Commands {
        CommandMenu("프리셋") {
            Button("프리셋 저장") { vm?.savePreset() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(vm == nil)
            Button("프리셋 불러오기") { vm?.loadPreset() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(vm == nil)
        }
    }
}

struct SettingsCommands: Commands {
    @FocusedObject private var vm: OrganizerViewModel?

    var body: some Commands {
        CommandMenu("환경설정") {
            Button("제외 목록 편집...") { vm?.showExcludeListEditor = true }
                .disabled(vm == nil)
            Button("로그 파일 열기") { vm?.openLogFolder() }
            Divider()
            Button("기본값으로 초기화") { vm?.resetToDefaults() }
                .disabled(vm == nil)
        }
    }
}
