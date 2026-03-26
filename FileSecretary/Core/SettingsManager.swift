import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    private init() {}

    private var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("FileSecretary", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_settings.json")
    }

    /// Load persisted user settings. Returns nil if not yet saved.
    func load() -> RulesData? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(RulesData.self, from: data)
    }

    /// Persist rules to Application Support.
    func save(_ rules: RulesData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    /// Remove saved file so next launch falls back to default_rules.json.
    func resetToDefault() {
        try? FileManager.default.removeItem(at: settingsURL)
    }

    // MARK: - Preset (user-chosen path)

    func savePreset(_ rules: RulesData, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rules)
        try data.write(to: url, options: .atomic)
    }

    func loadPreset(from url: URL) throws -> RulesData {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RulesData.self, from: data)
    }
}
