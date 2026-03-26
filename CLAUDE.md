# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a macOS SwiftUI app (macOS 13+). Build and run via Xcode — open `FileSecretary.xcodeproj`.

There are no test targets. There is no CLI build command; use Xcode or `xcodebuild`:
```
xcodebuild -project FileSecretary.xcodeproj -scheme FileSecretary -configuration Debug build
```

## Architecture

**Two-state window:** The app starts compact (260×220, not resizable). Dropping a folder triggers an animated expand to ≥820×580 (resizable). `ContentView` owns this state and branches into `CompactRootView` or `ExpandedRootView`.

**Two tabs:** 파일 정리 (File Organizer) and 파일명 편집 (File Renamer), toggled by `AppTab` enum in `ContentView`.

**MVVM + async/await:** `OrganizerViewModel` is the central state object for the organizer tab. It holds `targetFolders`, `outputFolders`, `categories`, `excludeList`, and dialog-trigger booleans. Long-running operations use `Task { @MainActor in await ... }` with `withCheckedContinuation` to pause for user dialogs.

**Menu commands** access the ViewModel via `OrganizerViewModel.current` (a `static weak var` set in `init()`). SwiftUI's `@FocusedObject`/`@FocusedValue` is unreliable in this window structure — do not use it.

**Organize flow:**
1. `OrganizerViewModel.startOrganize()` → `FileOrganizer.organize()`
2. `RuleEngine` evaluates each file against `Category` rules (type/keyword/both, AND/OR logic)
3. Conflicts/duplicates pause execution via async continuations and show dialogs
4. Moves are recorded in `UndoHistory`; `LogWriter` writes to `~/Library/Logs/FileSecretary/log/` and auto-saves XLSX to `~/Library/Logs/FileSecretary/xlsx/`

**Output folder routing:** Each category can route to output folder A/B/C/D (`outputIdx`) or default (first output folder). Max 4 output folders.

**Sandboxing:** The app is sandboxed (`FileSecretary.entitlements`). All folder access uses security-scoped bookmarks via `BookmarkManager`. Call `startAccessing`/`stopAccessing` around any file operations on user-selected URLs.

## Critical pbxproj Rule

When adding a new `.swift` source file, it must appear in **four** places in `project.pbxproj`:
1. PBXBuildFile section (buildFile UUID referencing the fileRef UUID)
2. PBXFileReference section (fileRef UUID with file path)
3. PBXGroup children (the fileRef UUID in the appropriate group)
4. PBXSourcesBuildPhase files (the buildFile UUID)

Missing any one of these causes build failures where the file's types/symbols are not found.

## Key Data Types

- `Category`: `id`, `num`, `name`, `conditionType` (.keyword/.type/.both), `types` ([FileTypeCategory]), `keywords` ([String]), `logic` (.and/.or), `outputIdx` (Int?)
- `RulesData`: Codable root for settings JSON (categories + excludeList + outputFolders)
- `OrganizeResult`: `moved` ([(from, to)]), `skipped` ([URL]), `errors` ([(file, error)])
- `DuplicateMode`: `.addNumber` / `.overwrite` / `.skip`
- `ConflictResolution`: used when a file matches multiple categories
- `VolumeInfo`: `name`, `totalBytes`, `usedBytes`, `freeBytes`, `isExternal`

## Disk Monitoring

`DiskMonitor` uses `FileManager.mountedVolumeURLs` to enumerate all volumes. ExFAT/non-APFS external drives return 0 for `volumeAvailableCapacityForImportantUsage` — always use `max(freeImportant, freeBasic)` with `volumeAvailableCapacity` as fallback.

## Settings Persistence

- User rules: `~/Library/Application Support/FileSecretary/user_settings.json`
- Bookmarks: `UserDefaults` (key: `"bookmark_<path>"`)
- Default rules: bundled `Resources/default_rules.json`
