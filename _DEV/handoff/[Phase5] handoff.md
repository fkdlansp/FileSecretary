# FileSecretary — 개발 핸드오프

작성일: 2026-03-27

---

## 현재 빌드 상태

**정상 빌드 · 동작 확인 완료.**
Phase 5 (파일명 편집 탭) 전체 점검 및 기능 추가 완료. 컴파일 에러 없음.

---

## 이번 세션에서 완료한 작업

### 1. 파일명 편집 탭 — 되돌리기 기능 추가
- `RenameViewModel`에 `undoStack: [[(from: URL, to: URL)]]` 추가
- `apply()` 실행 후 성공한 이동 배치를 스택에 push
- `undo()`: 스택 peek → 파일 역순 복원 → `removeLast()` (클릭 시가 아닌 완료 후 카운트 감소)
- 액션 바에 `↩ 되돌리기 (n)` 버튼 추가, `undoCount == 0`이면 회색 비활성화

### 2. 파일명 통일 기능 개편
**변경 전:** 체크박스 ON/OFF로 통일 모드 진입
**변경 후:** 체크박스 제거, 항상 노출된 구조

- **공통 이름** 필드 항상 표시 — 비어있으면 원본 파일명 유지
- **시작 번호** 기본값 빈값 — 비어있으면 번호 없이 저장, 숫자 입력 시 번호 적용
- **통일 방식** 항상 표시 — `통일명` (완전 교체) / `통일명(원본명)` (통일명(원본파일명) 형식)
- **번호 자릿수**: 시작 번호 없으면 흐리게 비활성화
- 안내 문구 컨트롤 바 하단에 항상 표시

### 3. 화면 A → 파일명 편집 탭 드롭 인식 수정
**변경 전:** 화면 A에서 파일명 탭으로 폴더 드롭 시 창은 확장되지만 폴더 미로드
**변경 후:** 정상 로드

- `ContentView`에 `renameFolderURL: URL?` 상태 추가
- `CompactRootView` 드롭 콜백: `.rename` 탭일 때 `renameFolderURL`에 저장
- `FileRenameView(initialFolderURL:)` — `onAppear` 시 `vm.loadFolder()` 호출

### 4. 파일명 편집 탭 — 폴더 제거 버튼 추가
- 폴더 헤더에 `xmark.circle.fill` 버튼 추가 → `vm.clearFolder()` 호출
- `clearFolder()`: folderURL, items, snapshot, undoStack, errorMessage 초기화

### 5. 경로 클릭 시 Finder 열기
- 대상 폴더, 출력 폴더, 파일명 편집 폴더 경로 텍스트 클릭 → `NSWorkspace.shared.open(url)`
- 기본 검정색, hover 시 accentColor로 변경
- 폴더 목록 아래 "경로를 클릭하면 Finder에서 열립니다" 안내 문구 공통 표시

### 6. 카테고리 추가/수정 모달 — 확장자 표시
**변경 전:** 타입 pill hover 시 tooltip으로만 확장자 표시
**변경 후:** 선택한 타입 아래에 확장자 항상 표시

- `CategoryModalView`에서 `selectedTypes`가 있을 때 타입별 확장자 목록 VStack으로 표시
- 형식: `이미지: jpg, jpeg, png, gif, bmp, tiff, heic, webp, svg`

### 7. 되돌리기 버튼 UX 통일 (파일 정리 탭 포함)
- count = 0: 회색 버튼, 클릭 불가 (기능 존재를 인지할 수 있도록 숨기지 않음)
- count > 0: 주황색 버튼, 클릭 가능
- 카운트는 파일 작업 완료 후에만 감소 (클릭 즉시 감소 아님)

---

## 현재 알려진 미확인 사항

| 항목 | 상태 | 비고 |
|------|------|------|
| 메뉴바 항목 실제 동작 | **유저 미확인** | static ref 패턴 적용 후 테스트 필요 |
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

### RenameViewModel 되돌리기 설계
```swift
func undo() {
    guard let last = undoStack.last, let folder = folderURL else { return }
    for pair in last.reversed() {
        try? FileManager.default.moveItem(at: pair.to, to: pair.from)
    }
    undoStack.removeLast()  // 작업 완료 후 pop
    loadFolder(folder)
}
```
`popLast()`를 먼저 호출하면 작업 도중 카운트가 감소함. 반드시 완료 후 `removeLast()`.

### 파일명 통일 설계 (체크박스 없는 구조)
- `unifiedBaseName`이 비어있으면 원본 파일명 유지 (자동 판단)
- `startNumberText`가 비어있으면 번호 없이 저장 (computed: `useNumbering`, `startNumber`)
- `unifyMode`: 0 = 완전 교체, 1 = 통일명(원본명) 형식

### async/await 다이얼로그 플로우 (파일 정리)
```
runOrganize() → FileOrganizer.organize()
    → duplicateHandler 콜백 → askDuplicateMode() → withCheckedContinuation
    → DuplicateFileDialog 표시 → confirmDuplicate() → continuation.resume()
    → 정리 재개
```
다이얼로그 콜백(confirmDuplicate, confirmUncategorized, resolveConflict)은 반드시 continuation을 resume해야 함.

---

## 파일 구조 요약

```
FileSecretary/
├── FileSecretaryApp.swift          앱 진입점 + 메뉴 Commands
├── ContentView.swift               윈도우 compact/expanded 상태 관리
├── Core/
│   ├── OrganizerViewModel.swift    메인 ViewModel (상태, 다이얼로그, 정리/되돌리기 진행)
│   ├── FileOrganizer.swift         파일 이동 핵심 로직
│   ├── RuleEngine.swift            카테고리 규칙 평가 + FileTypeCategory 정의
│   ├── DuplicateResolver.swift     중복 파일 처리
│   ├── FileRenamer.swift           파일명 변경 로직 + RenameItem 모델
│   ├── UndoHistory.swift           되돌리기 스택 (파일 정리용)
│   ├── LogWriter.swift             로그 기록 + XLSX 자동저장
│   ├── XLSXExporter.swift          Office Open XML XLSX 생성
│   ├── DiskMonitor.swift           볼륨 정보 수집 (5초 주기)
│   ├── BookmarkManager.swift       샌드박스 보안 스코프 북마크
│   └── SettingsManager.swift       설정 JSON 저장/로드
└── Views/
    ├── DiskStatusBar.swift         상단 디스크 상태바 (가로 스크롤)
    ├── FileOrganizerView.swift     파일 정리 탭 컨테이너
    ├── LeftPanelView.swift         대상/출력 폴더 패널
    ├── CategoryListView.swift      카테고리 목록 + 되돌리기/정리 버튼
    ├── CategoryCardView.swift      카테고리 카드 컴포넌트
    ├── CategoryModalView.swift     카테고리 추가/편집 모달 (선택 타입 확장자 표시)
    ├── DropZoneView.swift          compact 상태 드롭존
    ├── FileRenameView.swift        파일명 편집 탭 전체 (RenameViewModel 포함)
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
- **로그/XLSX 저장 위치** — `~/Library/Logs/FileSecretary/log/` (텍스트), `~/Library/Logs/FileSecretary/xlsx/` (자동 저장)
