# FileSecretary — Phase 9 개발 핸드오프

작성일: 2026-03-31

---

## 빌드 상태

**컴파일 에러 없음.** SourceKit 진단 오류는 전부 cross-file 타입 참조로 인한 LSP 캐시 문제 (pre-existing, 실제 빌드 무관).

---

## 이번 세션 업데이트 체크리스트

새 세션에서 아래 항목들을 빌드/실행으로 확인하세요.

- [ ] 파일명 편집 탭 — 파일 드롭 후 적용 시 실제 파일명 변경 확인 (sandbox 권한 수정)
- [ ] 파일명 편집 탭 — 적용 버튼 클릭 시 변경 후 이름 중복이면 alert 표시 확인
- [ ] 파일명 편집 탭 — alert "자동 넘버링" 선택 시 `소개로드.dmg`, `소개로드(2).dmg` 형식 확인
- [ ] 파일명 편집 탭 — alert "충돌 파일 건너뜀" 선택 시 중복 파일 선택 해제 후 나머지만 적용 확인
- [ ] 파일명 편집 탭 — 목록에 파일이 있는 상태에서 추가 드롭 → 리셋 없이 목록에 추가 확인
- [ ] 파일명 편집 탭 — 파일 드래그 호버 시 파란 테두리 + "파일 추가" 오버레이 표시 확인
- [ ] 파일명 편집 탭 — 액션바 "목록에서 제거" 버튼 명칭 확인
- [ ] 화면 A 파일 정리탭 — 파일 드롭 시 "파일 드롭은 파일명 편집 탭에서만 사용 가능합니다" 안내 오버레이 표시 확인
- [ ] 화면 A 파일 정리탭 — 위 안내 표시 후 탭 전환/확장 없음 확인
- [ ] Xcode 콘솔 — 파일 드롭 → 적용 전 과정에서 `[FileRenamer]`, `[RenameVM]` 디버그 로그 출력 확인

---

## 이번 세션에서 완료한 작업

### 1. 파일명 변경 작동 불가 — 샌드박스 권한 수정

**근본 원인:**
- 샌드박스 앱에서 개별 파일을 드래그하면 해당 파일에만 임시 읽기 접근권이 생김
- `FileManager.moveItem`은 대상 파일뿐 아니라 **부모 폴더 쓰기 권한**이 필요
- 기존 코드는 `BookmarkManager`를 전혀 사용하지 않아 `apply()` 시점에 권한 없음 에러

**에러 메시지:**
```
"파일명.ext" couldn't be moved because you don't have permission to access "폴더명"
```

**해결:**

`FileRenameView.swift` — `loadFolder()` / `loadFiles()` / `appendURLs()`:
- 파일/폴더 로드 시 `BookmarkManager.shared.saveBookmark(for: parentURL)` 호출
- 이 시점에는 드롭/NSOpenPanel 임시 접근권이 살아있어 북마크 저장 가능

`FileRenameView.swift` — `apply()` / `undo()`:
```swift
// 부모 폴더 북마크로 쓰기 접근 시작
let parentFolders = Set(selected.map { $0.originalURL.deletingLastPathComponent() })
var accessedBookmarkURLs: [URL] = []
for parent in parentFolders {
    if let bookmarkedURL = BookmarkManager.shared.restoreURL(for: parent.path) {
        if BookmarkManager.shared.startAccessing(bookmarkedURL) {
            accessedBookmarkURLs.append(bookmarkedURL)
        }
    }
}
defer {
    for url in accessedBookmarkURLs { BookmarkManager.shared.stopAccessing(url) }
}
```

**주의:** 북마크 없음 로그(`"북마크 없음: ..."`)가 콘솔에 뜨면 해당 폴더를 "폴더 선택" 버튼으로 다시 열어야 함.

---

### 2. 디버그 로그 추가

전 과정에 `print()` 추가:
- `[FileRenamer]`: 각 파일 rename 시도 결과 (성공/실패 이유)
- `[RenameVM]`: loadFolder/loadFiles 파일 수, apply 선택 수, undo 단계
- `[FileRenameView]`: handleDrop provider/URL 수집 과정

---

### 3. 중복 미리보기 경고 Alert

**흐름:**
1. 적용 버튼 → `checkAndApply()` 호출
2. 선택된 항목들의 미리보기 이름 계산
3. 중복 감지 시 Alert 표시

**Alert 선택지:**
- **자동 넘버링**: `소개로드.dmg` → `소개로드.dmg`, `소개로드(2).dmg`, `소개로드(3).dmg`
- **충돌 파일 건너뜀**: 중복에 연루된 **모든** 항목을 선택 해제 → 나머지만 적용, 해당 파일은 리스트에 유지
- **취소**: 아무 동작 없음

`FileRenamer.swift` — `resolveDuplicates: Bool` 파라미터 추가:
```swift
// 중복 자동 넘버링 로직
var seenCount: [String: Int] = [:]
for (i, name) in targetNames.enumerated() {
    seenCount[name, default: 0] += 1
    let count = seenCount[name]!
    if count > 1 {
        let ext = items[i].ext.isEmpty ? "" : ".\(items[i].ext)"
        let base = name.hasSuffix(ext) ? String(name.dropLast(ext.count)) : name
        targetNames[i] = "\(base)(\(count))\(ext)"
    }
}
```

---

### 4. 파일 추가 Append 모드

**변경 전:** 목록에 파일이 있는 상태에서 드롭하면 리셋 후 새로 로드
**변경 후:** 기존 목록 유지, 새 파일만 추가 (중복 URL 자동 제외)

`FileRenameView.swift` — `handleDrop()`:
```swift
if self.vm.items.isEmpty {
    self.applyInitialURLs(urls)  // 새로 로드
} else {
    self.vm.appendURLs(urls)     // 기존 목록에 추가
}
```

`RenameViewModel.appendURLs(_ urls: [URL])` 신규 메서드:
- 폴더 드롭 시 해당 폴더 내 파일 수집
- 이미 목록에 있는 URL 제외
- 부모 폴더 북마크 저장

---

### 5. 파일 정리탭 파일 드롭 안내

**변경 전:** 파일 정리탭에서 파일 드롭 → 자동으로 파일명 편집 탭으로 전환 + 확장 (UX 불명확)
**변경 후:** 탭 전환/확장 없이 드롭존 위에 안내 오버레이 표시 (2.8초 자동 사라짐)

```
파일 드롭은
파일명 편집 탭에서만
사용 가능합니다
```

`ContentView.swift` — `CompactRootView`:
- `@State private var showFileOnlyNotice = false`
- `fileOnlyNoticeOverlay` computed property 추가
- `hasFiles && selectedTab == .organizer` 조건 시 notice 표시 후 `return`

---

### 6. 파일명 편집 탭 드롭 시각 피드백

**변경 전:** 확장 뷰에서 파일 드래그해도 어디에 드롭할지 불분명 (`.onDrop` 있지만 시각 피드백 없음)
**변경 후:** 드래그 호버 시 전체 뷰에 파란 테두리 + 아이콘 오버레이

`FileRenameView.swift`:
```swift
@State private var isDropTargeted = false

.onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
.overlay(dropTargetOverlay)
```

`dropTargetOverlay`: 파란 테두리 + 아이콘 + 상태에 따라 "파일 또는 폴더 드롭" / "파일 추가" 텍스트

---

### 7. 버튼 명칭 변경

- 액션바 `제거` → `목록에서 제거` (파일 삭제가 아닌 목록에서만 제외임을 명확히)
- hover `-` 버튼 help: "목록에서 제외" (기존 유지)

---

## 파일 변경 목록

```
FileSecretary/
├── ContentView.swift           파일 정리탭 파일드롭 안내 오버레이
├── Core/
│   └── FileRenamer.swift       디버그 로그, resolveDuplicates, 실패 상세 에러
└── Views/
    └── FileRenameView.swift    sandbox 권한 수정, 중복 alert, append 모드,
                                드롭 시각 피드백, 목록에서 제거 명칭 변경
```

---

## 핵심 설계 결정 및 주의사항

### Sandbox 권한 — 북마크 저장 타이밍
`saveBookmark`는 반드시 **파일 로드 시점** (드롭 직후 또는 NSOpenPanel 응답 직후)에 호출해야 함. 이 시점에만 OS가 해당 경로에 대한 임시 접근권을 부여하므로 북마크 생성 가능. `apply()` 시점에 `saveBookmark`를 호출하면 이미 권한이 만료되어 실패함.

### 중복 자동 넘버링 — 첫 번째 항목 처리
`seenCount`가 1인 첫 번째 항목은 이름 변경 없음. 두 번째부터 `(2)`, `(3)` 순으로 suffix 추가. 따라서 `소개로드.dmg`가 3개이면: `소개로드.dmg`, `소개로드(2).dmg`, `소개로드(3).dmg`.

### checkAndApply vs apply 분리
`checkAndApply()`: 중복 감지 → alert 또는 `apply()` 호출
`apply(resolveDuplicates:)`: 실제 파일 rename 수행
Alert 버튼들은 `apply()` 또는 `applyWithAutoNumbering()` / `applySkippingDuplicates()`를 직접 호출.
