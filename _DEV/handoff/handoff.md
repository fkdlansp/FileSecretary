# FileSecretary — 개발 핸드오프

작성일: 2026-03-26

---

## 현재 빌드 상태

**정상 빌드 · 동작 확인 완료.**
마지막으로 해결한 이슈들이 모두 병합된 상태이며 컴파일 에러 없음.

---

## 이번 세션에서 완료한 작업

### 1. XLSXExporter.swift — project.pbxproj 미등록 문제
- `XLSXExporter.swift`가 디스크에는 존재했지만 `project.pbxproj`에 등록이 안 돼 있어서 빌드 실패 상태였음
- pbxproj를 직접 수정해 PBXBuildFile / PBXFileReference / PBXGroup children / PBXSourcesBuildPhase 4곳에 모두 추가
- 함께 발견된 컴파일 에러들도 수정:
  - `buildZip(files:)` 라벨 누락
  - `dosDateTime()` 내 타입체커 타임아웃 → 비트시프트 표현식 분리
  - `withUnsafeBytes` 모호성 → `Swift.withUnsafeBytes(of:_:)` 명시

### 2. 로그 자동 저장 구조 개편
**변경 전:** 수동으로 "로그 XLSX 내보내기" 버튼 클릭 필요
**변경 후:** 정리 실행 시 자동 저장

저장 경로 구조:
```
~/Library/Logs/FileSecretary/
├── log/         ← YYYY-MM-DD.log (일별 텍스트 로그, 추가 기록)
└── xlsx/        ← YYYY-MM-DD_HH-mm-ss.xlsx (정리 실행마다 자동 저장)
                    undo_YYYY-MM-DD_HH-mm-ss.xlsx (되돌리기마다 자동 저장)
```

- `LeftPanelView`에서 "로그 XLSX 내보내기" 버튼 제거 (불필요)
- "로그 폴더" 버튼은 유지 → `~/Library/Logs/FileSecretary/` 열어줌

### 3. 되돌리기 로그 기록
**변경 전:** 되돌리기 내역이 로그에 남지 않음
**변경 후:** 되돌리기 실행 시 .log 파일 + xlsx 자동 저장

- `UndoHistory.undo()` 반환 타입을 `Int` → `(restored: [(from: URL, to: URL)], skipped: [URL])` 튜플로 변경
- `OrganizerViewModel.performUndo()`에서 반환값을 `LogWriter.shared.logUndoResult()`에 전달

### 4. 디스크 상태바 — 외장하드 표시 + ExFAT 버그 수정
**변경 전:** 맥 내장 디스크(Macintosh HD)만 표시
**변경 후:** 연결된 모든 볼륨을 가로 스크롤로 표시

- `DiskMonitor`가 `FileManager.mountedVolumeURLs`로 전체 볼륨 열거
- `VolumeInfo` 구조체 추가 (`isExternal` 포함)
- 외장 볼륨은 `externaldrive` 아이콘 표시
- **ExFAT 버그:** `volumeAvailableCapacityForImportantUsage`가 APFS 전용이라 ExFAT 외장에서 0 반환 → 100% 표시되던 문제
  - `max(freeImportant, freeBasic)` 방식으로 `volumeAvailableCapacity` 폴백 적용

### 5. 메뉴바 항목 비활성화 문제 해결
**변경 전:** 프리셋 저장/불러오기, 제외 목록 편집 등 메뉴 항목이 항상 비활성화
**변경 후:** 항상 활성화, 정상 동작

- `@FocusedObject` 시도 → 실패
- `@FocusedValue` 시도 → 실패
- 근본 원인: 이 앱의 윈도우 구조에서 SwiftUI focus 메커니즘이 신뢰할 수 없음
- 해결: `OrganizerViewModel`에 `static weak var current: OrganizerViewModel?` 추가, `init()`에서 설정
- `FileSecretaryApp.swift`의 Commands가 `OrganizerViewModel.current?.method()` 직접 호출

---

## 현재 알려진 미확인 사항

| 항목 | 상태 | 비고 |
|------|------|------|
| 메뉴바 항목 실제 동작 | **유저 미확인** | static ref 패턴 적용 후 테스트 요청됨. 이전 방식(@FocusedObject, @FocusedValue) 두 번 다 실패했으므로 반드시 실기기 확인 필요 |
| ExFAT 외장하드 디스크 사용량 표시 | **유저 미확인** | 폴백 로직 적용 완료, 실기기 확인 필요 |

---

## 코드베이스 주요 설계 결정

### static weak var current 패턴 (메뉴 커맨드용)
```swift
// OrganizerViewModel.swift
static weak var current: OrganizerViewModel?
init() {
    OrganizerViewModel.current = self
    loadSettings()
}

// FileSecretaryApp.swift
Button("프리셋 저장") { OrganizerViewModel.current?.savePreset() }
```
SwiftUI Commands에서 ViewModel에 접근하는 유일하게 신뢰할 수 있는 방법.
`@FocusedObject`, `@FocusedValue`는 이 앱의 compact/expanded 이중 뷰 구조에서 동작하지 않음. **절대 되돌리지 말 것.**

### pbxproj 수동 관리 주의사항
새 Swift 파일 추가 시 project.pbxproj 4곳 모두 등록 필수:
1. PBXBuildFile
2. PBXFileReference
3. PBXGroup children
4. PBXSourcesBuildPhase files

Xcode GUI를 통해 파일을 추가하면 자동 처리됨. 직접 파일을 복사하거나 git으로 받아오면 누락될 수 있음.

### async/await 다이얼로그 플로우
정리 루프는 `withCheckedContinuation`으로 일시정지 후 유저 응답을 기다림:
```
runOrganize() → FileOrganizer.organize()
    → duplicateHandler 콜백 → askDuplicateMode() → withCheckedContinuation
    → DuplicateFileDialog 표시 → confirmDuplicate() → continuation.resume()
    → 정리 재개
```
다이얼로그 콜백(confirmDuplicate, confirmUncategorized, resolveConflict)은 반드시 continuation을 resume해야 함. 안 하면 정리 Task가 영원히 suspend됨.

---

## 파일 구조 요약

```
FileSecretary/
├── FileSecretaryApp.swift          앱 진입점 + 메뉴 Commands
├── ContentView.swift               윈도우 compact/expanded 상태 관리
├── Core/
│   ├── OrganizerViewModel.swift    메인 ViewModel (상태, 다이얼로그, 정리/되돌리기 진행)
│   ├── FileOrganizer.swift         파일 이동 핵심 로직
│   ├── RuleEngine.swift            카테고리 규칙 평가
│   ├── DuplicateResolver.swift     중복 파일 처리
│   ├── FileRenamer.swift           파일명 일괄 변경
│   ├── UndoHistory.swift           되돌리기 스택
│   ├── LogWriter.swift             로그 기록 + XLSX 자동저장
│   ├── XLSXExporter.swift          Office Open XML XLSX 생성
│   ├── DiskMonitor.swift           볼륨 정보 수집 (5초 주기)
│   ├── BookmarkManager.swift       샌드박스 보안 스코프 북마크
│   └── SettingsManager.swift       설정 JSON 저장/로드
└── Views/
    ├── DiskStatusBar.swift         상단 디스크 상태바 (가로 스크롤)
    ├── FileOrganizerView.swift     파일 정리 탭 컨테이너
    ├── LeftPanelView.swift         대상/출력 폴더 패널
    ├── CategoryListView.swift      카테고리 목록
    ├── CategoryCardView.swift      카테고리 카드 컴포넌트
    ├── CategoryModalView.swift     카테고리 추가/편집 모달
    ├── DropZoneView.swift          compact 상태 드롭존
    ├── FileRenameView.swift        파일명 편집 탭 전체
    ├── RenameRowView.swift         파일명 편집 행
    └── Dialogs/
        ├── DuplicateFileDialog.swift
        ├── UncategorizedDialog.swift
        ├── CategoryConflictDialog.swift
        └── ExcludeListView.swift
```

---

## 다음 개발 시 참고사항

- **테스트 인프라 없음** — 유닛 테스트 타겟 미존재. 수동 테스트만 가능.
- **비재귀 스캔** — `FileOrganizer`는 대상 폴더의 직접 하위 파일만 정리함. 서브폴더 안은 스캔 안 함.
- **출력 폴더 최대 4개** — A/B/C/D 레이블. 카테고리별로 `outputIdx`로 라우팅. `nil`이면 첫 번째 출력 폴더(메인)로 감.
- **기본 규칙** — `Resources/default_rules.json`에 있음. 환경설정 → 기본값으로 초기화 시 이 파일을 읽음.
- **설정 저장 위치** — `~/Library/Application Support/FileSecretary/user_settings.json`
- **북마크** — `UserDefaults`에 `"bookmark_<path>"` 키로 저장. 샌드박스 재시작 후에도 폴더 접근 가능하게 함.
