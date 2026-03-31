# FileSecretary — Phase 8 개발 핸드오프

작성일: 2026-03-31

---

## 빌드 상태

**컴파일 에러 없음.** SourceKit 진단 오류는 전부 cross-file 타입 참조로 인한 LSP 캐시 문제 (pre-existing, 실제 빌드 무관).

---

## 이번 세션 업데이트 체크리스트

새 세션에서 아래 항목들을 빌드/실행으로 확인하세요.

- [ ] 파일명 편집 탭 — 폴더 모드에서 적용 후 되돌리기 버튼 활성화 확인
- [ ] 파일명 편집 탭 — 연속 되돌리기 (2회 이상) 동작 확인
- [ ] 파일명 편집 탭 — 되돌리기 후 로그/xlsx 생성 확인 (`xlsx/rename/undo_name_...xlsx`)
- [ ] 파일명 편집 탭 — 행 hover 시 `-` 버튼 표시 및 개별 제거 동작
- [ ] 파일명 편집 탭 — 체크 후 하단 `제거` 버튼으로 일괄 제거 동작
- [ ] 파일 정리 탭 — 다중 폴더 드롭 시 race condition 없이 모두 추가되는지 확인
- [ ] 파일명 편집 탭 — 다중 폴더 드롭 시 각 폴더 파일 합산 로드 확인
- [ ] 로그 폴더 구조: `FileSecretary/*.log`, `xlsx/move/`, `xlsx/download/`, `xlsx/rename/`
- [ ] 다운로드 정리 로그 → `xlsx/download/` 저장 확인
- [ ] 다운로드 되돌리기 로그 → `xlsx/download/undo_...xlsx` 확인
- [ ] 파일 정리 — 출력폴더에 01,04 카테고리만 있을 때 `01_이미지`, `02_어도비`로 상대 넘버링 확인
- [ ] 파일 정리 — 재정리 시 기존 `02_어도비`가 `03_어도비`로 자동 밀림 확인
- [ ] 카테고리 카드 — 폴더명 `01_이미지` 텍스트 노출 확인
- [ ] 카테고리 추가/수정 모달 — 입력 필드 레이블 `폴더명` 표시 확인
- [ ] 화면 A(compact)에서 파일 드래그 → 파일명 편집 탭 자동 전환 + 파일 로드 확인
- [ ] 화면 A에서 폴더 드래그 (organizer 탭) → 기존처럼 파일 정리 탭 정상 동작 확인

---

## 이번 세션에서 완료한 작업

### 1. 드래그앤드롭 버그 2종 수정

#### LeftPanelView.swift — race condition
**문제:** `handleDrop`에서 여러 백그라운드 스레드가 `urls` 배열에 동시 append → Swift 배열 undefined behavior, 간헐적 crash 또는 데이터 손상

**원인:**
```swift
// 수정 전 (위험)
var urls: [URL] = []
provider.loadItem(...) { ... urls.append(url) }  // 다중 스레드 동시 접근
```

**해결:** 인덱스 기반 pre-sized 배열로 교체 — 각 콜백이 독립 슬롯에만 씀
```swift
var collectedURLs: [URL?] = Array(repeating: nil, count: providers.count)
provider.loadItem(...) { collectedURLs[i] = url }
```

#### FileRenameView.swift — 다중 폴더 드롭 무시
**문제:** 다중 폴더 드롭 시 디렉토리 필터(`!isDir.boolValue`)로 전부 제외 → 아무것도 로드 안됨

**해결:** 다중 폴더 케이스 추가 — 각 폴더의 파일을 합산해 `loadFiles()` 호출

---

### 2. 파일명 편집 undo 치명적 버그 2종 수정

#### Bug A — 적용 직후 undo 항상 불가
**원인:** `apply()` 실행 순서 문제
```swift
// 수정 전 (버그)
undoStack.append(result.renamed)  // 1. 스택에 추가
...
loadFolder(folder)                 // 2. loadFolder 내부에서 undoStack = [] → 즉시 삭제!
```

**해결:** `loadFolder` 호출 후 스택에 추가
```swift
// 수정 후
loadFolder(folder)                 // 1. 폴더 갱신 (내부에서 undoStack = [])
if !result.renamed.isEmpty {
    undoStack.append(result.renamed)  // 2. 그 다음 스택에 추가
}
```

#### Bug B — 연속 undo 불가 (2회째부터 stack 소실)
**원인:** `undo()` 내부에서 `loadFolder()` 호출 시 남은 stack까지 삭제

**해결:** `remainingStack` 저장 후 복원
```swift
let remainingStack = Array(undoStack.dropLast())
...
loadFolder(folder)              // undoStack = [] 실행됨
undoStack = remainingStack      // 남은 스택 복원
```

#### Bug C — undo 로그 미기록
**원인:** `undo()` 함수에 로그 호출 없음. `try?`로 성공/실패 무시

**해결:** 성공/실패 추적 후 `LogWriter.shared.logRenameUndoResult()` 호출

---

### 3. 로그/XLSX 폴더 구조 재설계

**변경 전:**
```
FileSecretary/
├── log/yyyy-MM-dd.log
└── xlsx/TIMESTAMP.xlsx, undo_TIMESTAMP.xlsx, rename_TIMESTAMP.xlsx
```

**변경 후:**
```
FileSecretary/
├── yyyy-MM-dd.log                    ← .log 최상위 직접 저장
└── xlsx/
    ├── move/                         ← 파일 정리
    │   ├── TIMESTAMP.xlsx
    │   └── undo_TIMESTAMP.xlsx
    ├── download/                     ← 다운로드 정리
    │   ├── TIMESTAMP.xlsx
    │   └── undo_TIMESTAMP.xlsx
    └── rename/                       ← 파일명 수정
        ├── name_TIMESTAMP.xlsx
        └── undo_name_TIMESTAMP.xlsx
```

**LogWriter.swift 변경 내역:**
- `logSubfolderURL` 제거 → `todayLogURL`이 `logFolderURL` 직접 사용
- `xlsxSubfolderURL` 제거 → `xlsxMoveFolderURL`, `xlsxDownloadFolderURL`, `xlsxRenameFolderURL` 3개로 분리
- `logDownloadResult(result:downloadsURL:)` 추가
- `logDownloadUndoResult(restored:skipped:)` 추가
- `logRenameUndoResult(restored:skipped:)` 추가
- `logRenameResult` 저장 경로: `xlsx/rename/name_TIMESTAMP.xlsx`

---

### 4. 다운로드 undo 로그 분리

**UndoHistory.swift — Source 추가:**
```swift
struct UndoEntry {
    enum Source { case organize, download }
    let moves: [(from: URL, to: URL)]
    let source: Source
}

func push(_ result: OrganizeResult, source: UndoEntry.Source = .organize)
func undo() -> (restored:..., skipped:..., source: UndoEntry.Source)
```

**OrganizerViewModel.swift:**
- `organizeDownloads()`: `undoHistory.push(result, source: .download)`
- `performUndo()`: source가 `.download`면 `logDownloadUndoResult`, `.organize`면 `logUndoResult`

---

### 5. 파일명 편집 목록 개별 제외 기능

**RenameViewModel:**
```swift
func removeItem(id: UUID)          // 개별 제거
func removeSelectedItems()         // 체크된 항목 일괄 제거
private func updateAfterRemove()   // items/snapshot/fileModeCount/folderURL 동기화
```

**RenameRowView.swift:**
- `onRemove: () -> Void` 파라미터 추가
- `@State private var isHovered = false` 추가
- hover 시 `-` 버튼 표시 (opacity 0→1)

**FileRenameView 액션바:**
- `제거` 버튼 추가 — 선택 항목 없으면 비활성화
- 컬럼 헤더에 16pt 공간 추가 (× 버튼 정렬)

---

### 6. 출력폴더 상대 넘버링 + 기존 폴더 자동 재정렬

**FileOrganizer.swift — buildFolderNumberMap():**
- 정리 전 파일 사전 스캔 → 각 출력폴더에 실제 들어올 카테고리 파악
- 해당 폴더의 기존 `NN_name` 폴더도 포함
- 카테고리 `num` 오름차순 정렬 → 01, 02, 03... 상대 번호 부여

**FileOrganizer.swift — reconcileFolderNumbers():**
- 정리 완료 후 출력폴더 순회
- 기존 `NN_name` 폴더 중 번호가 바뀐 것 감지
- 임시명 → 최종명 2단계 rename (충돌 방지)
- 대상 폴더 이미 존재 시 파일 병합

**예시:**
```
[이전 상태] 01_이미지  02_어도비(num=4)
[동영상(num=2) 추가 후]
→ buildFolderNumberMap: 이미지=1, 동영상=2, 어도비=3
→ 신규 파일: 02_동영상 폴더에 저장
→ reconcile: 02_어도비 → (임시) → 03_어도비
[최종] 01_이미지  02_동영상  03_어도비
```

---

### 7. UI 명칭 변경

**CategoryModalView.swift:**
- 입력 필드 레이블: `카테고리명` → `폴더명`
- placeholder: `이름 입력` → `폴더명 입력`

**CategoryCardView.swift:**
- 카테고리명 옆에 `폴더명: 01_이미지` 소문자 표시 추가

---

### 8. 화면 A(compact) → 화면 B(expanded rename) 파일 드래그 지원

**DropZoneView.swift:**
- `loadURLs`: tab 기반 필터 제거 → 모든 파일/폴더 수용, 라우팅은 호출자에서 처리

**ContentView.swift:**
- `renameFolderURL: URL?` → `renameDropURLs: [URL]` 로 교체
- `CompactRootView.handleDrop`:
  - 드롭된 URL 중 파일(non-directory) 포함 → `selectedTab = .rename` 자동 전환, `renameDropURLs = urls`
  - 폴더만 + rename 탭 → `renameDropURLs = urls`
  - 폴더만 + organizer 탭 → 기존처럼 `targetFolders` 업데이트

**FileRenameView.swift:**
- `initialFolderURL: URL?` → `initialURLs: [URL]`
- `onAppear`: `applyInitialURLs(initialURLs)` 호출
- `applyInitialURLs(_:)` 추가 — `handleDrop`의 URL 처리 로직을 공유 함수로 분리:
  - 단일 폴더 → `loadFolder()`
  - 다중 폴더 → 각 폴더 파일 합산 `loadFiles()`
  - 파일들 → `loadFiles()`

---

## 파일 변경 목록

```
FileSecretary/
├── ContentView.swift               renameDropURLs, CompactRootView 드롭 라우팅
├── Core/
│   ├── LogWriter.swift             폴더 구조 재설계, 메서드 3개 추가
│   ├── OrganizerViewModel.swift    logDownloadResult 호출, undo source 분기
│   ├── UndoHistory.swift           UndoEntry.Source enum, push/undo 시그니처 변경
│   └── FileOrganizer.swift         buildFolderNumberMap, reconcileFolderNumbers 추가
└── Views/
    ├── DropZoneView.swift          loadURLs 필터 제거
    ├── FileRenameView.swift        undo 버그 2종 수정, removeItem, initialURLs, applyInitialURLs
    ├── RenameRowView.swift         onRemove, isHovered, × 버튼
    ├── CategoryModalView.swift     폴더명 레이블
    └── CategoryCardView.swift      폴더명 표시 추가
```

---

## 핵심 설계 결정 및 주의사항

### loadFolder는 undoStack을 초기화한다
`loadFolder()` 내부에 `undoStack = []`이 있음. apply/undo 흐름에서 loadFolder 이후에 스택 조작 필요.
- `apply()`: loadFolder 후 `undoStack.append()`
- `undo()`: remainingStack 저장 → loadFolder → `undoStack = remainingStack`

### 출력폴더 상대 넘버링 사전 스캔
`buildFolderNumberMap`은 정리 루프 이전에 실행. async 다이얼로그 없이 첫 번째 매칭 카테고리만 사용 (간략 스캔). 정확도보다 속도 우선 — 실제 정리에서 충돌/미분류 핸들러가 별도 처리.

### reconcileFolderNumbers 2단계 rename
1단계: 대상 폴더들을 UUID 임시명으로 이동
2단계: 임시명 → 최종명 이동 (이미 존재하면 파일 병합)
단계 분리 이유: rename 순서에 따른 충돌(A→B, B→C 동시) 방지

### DropZoneView 탭 필터 제거
이전: `tab == .rename || isDir.boolValue` 필터
이후: 필터 없음, CompactRootView가 파일 감지 후 탭 전환 결정
영향: organizer 탭에서 파일 드래그해도 DropZoneView가 수용 → CompactRootView에서 rename 탭으로 자동 전환
