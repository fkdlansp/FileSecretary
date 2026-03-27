# FileSecretary — 개발 핸드오프

작성일: 2026-03-27

---

## 현재 빌드 상태

**정상 빌드 · 동작 확인 완료.**
Phase 7 버그 수정 및 기능 추가 완료. 컴파일 에러 없음.

---

## 이번 세션에서 완료한 작업

### 1. 미확인 항목 전체 확인 완료 (Phase 6-1 이월)

- 메뉴바 항목 동작 확인
- ExFAT 외장하드 디스크 사용량 표시 확인
- OutputDropdown 스트로크 박스 렌더링 확인

### 2. 개별 모드 OutputDropdown 테두리 박스 수정

**문제:** `selectedIdx == 0` (개별 모드)일 때 테두리 박스가 보이지 않음

**원인:** padding을 Menu label 내부 Text에 적용했는데, `.menuStyle(.borderlessButton)`이 label 내부 padding을 무시함

**해결:** padding을 Menu 뷰 자체에 적용 (`.menuStyle(.borderlessButton)` 뒤에)
```swift
Menu { ... } label: { Text(selectedLabel)... }
.menuStyle(.borderlessButton)
.padding(.leading, 10)
.padding(.trailing, 8)
.padding(.vertical, 5)
.frame(minWidth: 100, maxWidth: 160, alignment: .leading)
.overlay(RoundedRectangle(cornerRadius: 5).stroke(..., lineWidth: 1.5))
```
- 폰트: 10 → 12
- 테두리 두께: 0.5 → 1.5
- 최소 너비: 80 → 100

### 3. 원클릭 다운로드 정리 수정

**문제:** 실행해도 아무것도 안 됨

**원인 1:** `com.apple.security.files.downloads.read-write` 엔타이틀먼트 누락
→ `FileSecretary.entitlements`에 추가

**원인 2 (핵심):** 샌드박스에서 `FileManager.urls(for: .downloadsDirectory)` 가 심볼릭 링크 경로(`/Users/.../Containers/.../Data/Downloads`)를 반환. `contentsOfDirectory(at:url:)` API는 심링크 루트를 따라가지 않아 `NSPOSIXErrorDomain Code=20 "Not a directory"` 에러 발생

**해결:** `.resolvingSymlinksInPath()` 로 실제 경로 해소
```swift
let downloadsURL = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
    .resolvingSymlinksInPath()
// 결과: /Users/rev_imac1/Downloads (실제 경로)
```

**추가:** `try?` → `do/catch` 로 변경해 에러를 LogWriter에 기록

### 4. 파일명 편집 탭 — 개별 파일 드래그 지원

**기존:** 폴더 드래그만 지원 (폴더 내 전체 파일 로드)

**추가:** 파일 드래그 시 해당 파일들만 목록에 올라오는 모드
- `RenameViewModel.fileMode: Bool` 추가
- `RenameViewModel.loadFiles(_ urls: [URL])` 추가
- `handleDrop`: 단일 폴더 → 폴더 모드, 파일(들) → 파일 모드
- `apply()`: 파일 모드에서 `loadFolder(folder)` 대신 `refreshItemURLs()` — items URL만 갱신, 폴더 전체 재스캔 없음
- `undo()`: 파일 모드에서 items URL 역방향 갱신
- 헤더 표시:
  - 같은 폴더 파일: `~/경로  ·  N개 파일`
  - 다른 폴더 파일: `N개 파일 선택됨 (여러 폴더)`
  - 드롭 안내 문구: "폴더 또는 파일을 여기에 드롭하거나 폴더를 선택하세요"

### 5. 파일명 편집 탭 — 로그 기록 추가

- `LogWriter.logRenameResult(renamed:failed:folder:)` 추가
- `RenameViewModel.apply()` 후 호출 → `.log` 파일 + XLSX 자동 저장
- XLSX 파일명: `rename_yyyy-MM-dd_HH-mm-ss.xlsx`

### 6. 화면 A (CompactRootView) — 다운로드 폴더 정리 버튼

- `organizerVM: OrganizerViewModel` 파라미터 추가 (`@ObservedObject`)
- 파란 배경 + 흰 폰트 버튼
- 클릭 시 창 확장 없이 인라인 상태 표시:
  - 기본: "다운로드 폴더 정리" (파란 배경)
  - 진행 중: "정리 중..." + 스피너
  - 완료: "완료 · N개 이동" (파란 배경, 초록 아이콘)
  - 오류: "오류 발생 (로그 확인)" (빨간 배경)
- 정리 후 `undoCount > 0` 이면 되돌리기 버튼 표시 (주황 배경), 0이면 숨김
- `OrganizerViewModel.downloadResultMessage: String?` Published 추가

### 7. NSHostingView 레이아웃 재귀 경고 수정

**문제:** `layoutSubtreeIfNeeded on a view which is already being laid out`

**원인:** `WindowFinder.makeNSView`의 `viewDidMoveToWindow`와 `updateNSView`에서 SwiftUI 렌더 사이클 중 `configureWindow(window:)`를 동기 호출 → 레이아웃 재귀

**해결:** 두 경로 모두 `DispatchQueue.main.async`로 다음 런루프로 지연
```swift
// makeNSView
v.onFound = { window in
    DispatchQueue.main.async {
        context.coordinator.install(on: window)
        self.onFound(window)
    }
}
// updateNSView
func updateNSView(_ nsView: CapturingView, context: Context) {
    if let w = nsView.window {
        DispatchQueue.main.async { self.onFound(w) }
    }
}
```

---

## 파일 변경 목록

```
FileSecretary/
├── FileSecretary.entitlements        com.apple.security.files.downloads.read-write 추가
├── ContentView.swift                 CompactRootView 다운로드 버튼, WindowFinder async 수정
├── Core/
│   ├── OrganizerViewModel.swift      organizeDownloads 수정, downloadResultMessage 추가
│   ├── FileOrganizer.swift           organizeDownloads(at:) URL 파라미터 + symlink 해소
│   └── LogWriter.swift               logRenameResult() 추가
└── Views/
    ├── CategoryCardView.swift        OutputDropdown 테두리/패딩/폰트 수정
    └── FileRenameView.swift          파일 드래그 모드, 로그 호출
```

---

## 코드베이스 주요 설계 결정

### 샌드박스 Downloads 접근
```swift
// 반드시 .resolvingSymlinksInPath() 사용
// urls(for: .downloadsDirectory) → 컨테이너 심링크 반환
// contentsOfDirectory(at:url:) 는 심링크 루트를 따라가지 않음
let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    .first!.resolvingSymlinksInPath()
// → /Users/username/Downloads (실제 경로)
```

### OutputDropdown 패딩 규칙
```swift
// label 내부 padding은 .borderlessButton이 무시함
// padding은 반드시 .menuStyle(.borderlessButton) 뒤 Menu 뷰에 적용
Menu { ... } label: { Text(...) }
    .menuStyle(.borderlessButton)
    .padding(...)   // ← 여기에
    .overlay(...)
```

### WindowFinder 레이아웃 재귀 방지
- `makeNSView`와 `updateNSView` 모두 `DispatchQueue.main.async`로 감싸야 함
- SwiftUI 렌더 사이클 중 NSWindow 속성 수정은 항상 비동기로

### 파일명 편집 파일 모드
- `fileMode: Bool` — true이면 폴더 재스캔 없이 items URL만 갱신
- `apply()` 후: `fileMode ? refreshItemURLs() : loadFolder(folder)`
- `folderURL` — 파일 모드에서도 표시용으로 사용 (같은 부모 폴더일 때만 설정)

---

## 다음 개발 시 참고사항

- **다운로드 정리 URL**: 항상 `.resolvingSymlinksInPath()` 적용. 샌드박스 컨테이너 심링크 문제 재발 가능성 있음
- **OutputDropdown**: padding은 Menu 뷰 자체에 적용. label 내부 적용 금지
- **WindowFinder**: configureWindow 호출 경로는 반드시 async. 동기 호출 시 레이아웃 재귀 발생
- **파일명 편집 파일 모드**: `fileMode == true` 시 `folderURL`은 표시용 전용, 파일 목록 소스가 아님
