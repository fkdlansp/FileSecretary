# FileSecretary — 개발 핸드오프

작성일: 2026-03-27

---

## 현재 빌드 상태

**정상 빌드 · 동작 확인 완료.**
Phase 6-1 기능 추가 및 UI/UX 개선 완료. 컴파일 에러 없음.

---

## 이번 세션에서 완료한 작업

### 1. 기타 카테고리 — 출력폴더 지정 기능

- `RulesData`에 `etcOutputIdx: Int` 추가 (기존 저장 파일 하위호환: custom decoder로 누락 시 0 처리)
- `OrganizerViewModel`에 `@Published var etcOutputIdx: Int = 0` 추가
- `loadSettings()` / `saveSettings()` / `updateEtcOutputIdx()` 처리
- `FileOrganizer.organize()`에 `etcOutputIdx: Int = 0` 파라미터 추가
  - `etcOutputIdx > 0`이면 다이얼로그 없이 해당 출력폴더/기타로 자동 이동
  - 0이면 기존 `uncategorizedHandler` 다이얼로그 동작 유지
- `EtcCategoryRow`에 `OutputDropdown` 추가 (다른 카테고리 카드와 동일 UI)
- `OutputDropdown`에서 `private` 제거 → 다른 파일에서 재사용 가능

### 2. 출력모드 재실행 시 초기화

- `loadSettings()` 에서 `categories[].outputIdx`를 모두 0으로 리셋
- `etcOutputIdx`도 0으로 리셋
- **이유:** 출력폴더 순서가 세션마다 달라질 수 있어 저장된 인덱스가 엉뚱한 폴더를 가리킬 수 있음

### 3. 되돌리기 — 정리 시 생성된 빈 폴더 삭제

- `UndoHistory.undo()` 에서 파일 복원 후 정리 시 생성된 폴더(`move.to` 부모) 목록 수집
- 복원 완료 후 해당 폴더가 비어 있으면 `FileManager.removeItem()` 으로 삭제
- 다른 파일이 남아 있으면 삭제하지 않음

### 4. CategoryListView 레이아웃 변경

**순서 변경 (위 → 아래):**
- 변경 전: 원클릭/도구 → 액션바
- 변경 후: 액션바(제외목록·되돌리기·지금 정리하기) → 원클릭/도구

**버튼 통일:**
- 원클릭 섹션 "지금 정리" 버튼: `SmallButtonStyle` → `ActionButtonStyle` (액션바 버튼과 동일 크기)

**텍스트 수정:**
- 섹션 헤더: "원 클릭 다운로드" → "원 클릭 다운로드 폴더 정리"
- 버튼: "지금 정리" → "다운로드 정리"

### 5. 창 크기 고정 (리사이즈 완전 차단)

**문제:** `styleMask.remove(.resizable)`은 SwiftUI가 렌더링 사이클마다 `.resizable`을 다시 추가해서 효과 없음

**해결:** `NSWindowDelegate.windowWillResize(_:to:)` 가로채기
- `ResizeLockCoordinator: NSObject, NSWindowDelegate` 추가
- `windowWillResize`에서 항상 `sender.frame.size` 반환 → 드래그 리사이즈 차단
- 프로그래밍적 `setFrame` (전환 애니메이션)은 이 delegate를 거치지 않으므로 정상 동작
- 기존 delegate 포워딩: `responds(to:)` + `forwardingTarget(for:)` 오버라이드
- `WindowFinder.updateNSView`에서도 `onFound` 호출 → SwiftUI 업데이트 시에도 설정 유지

### 6. 창 크기 확장 및 패딩

- **창 크기:** `730×570` → `820×640`
- **콘텐츠 패딩:** 하단 14px만 적용 (좌우 패딩은 억지로 늘린 느낌이라 제거)
- **좌측 패널 너비:** `210px` → `240px` (경로 텍스트 잘림 개선)

### 7. DiskStatusBar 정렬 및 간격

- 볼륨 아이템: 좌정렬 유지, 외부 패딩 제거
- 아이템 간 내부 패딩: `20px` → `32px` (항목 사이 여백 증가)
- `VStack(alignment: .leading)` 명시적 지정 유지

### 8. OutputDropdown 스트로크 박스

- `.menuStyle(.borderlessButton)` + `.fixedSize()` + `.overlay(RoundedRectangle.stroke(...))` 조합
- 배경이 아닌 Menu 뷰 자체에 stroke 적용 → 테두리 박스 표시
- **이유:** label 내부의 `.background()`는 borderlessButton 스타일이 무시함

### 9. 파일명 편집 탭 — 화살표 가운데 배치

- 원본 파일명, 변경 후 미리보기 컬럼 모두 `maxWidth: .infinity`로 동일 너비
- 화살표(`arrow.right`)가 두 컬럼 사이 정중앙에 위치
- 컬럼 헤더도 동일하게 정렬 (투명 화살표 placeholder로 정렬 맞춤)

### 10. 파일명 편집 탭 — 체크박스 선택

- `RenameItem`에 `isSelected: Bool = true` 추가 (기본 전체선택)
- `RenameRowView`에 개별 체크박스 `Toggle(.checkbox)` 추가
- 컬럼 헤더에 전체선택/해제 버튼 추가 (`checkmark.square.fill` / `square` 아이콘)
- 미체크 항목: 글자 흐리게 표시, `apply()` 시 제외
- `previewName()`: 선택된 항목 기준으로 순번 재계산 → 체크 해제해도 번호 연속 유지
- `apply()`: `items.filter { $0.isSelected }` 후 `FileRenamer`에 전달

---

## 현재 알려진 미확인 사항

| 항목 | 상태 | 비고 |
|------|------|------|
| 메뉴바 항목 실제 동작 | **유저 미확인** | static ref 패턴 적용 후 테스트 필요 |
| ExFAT 외장하드 디스크 사용량 표시 | **유저 미확인** | 폴백 로직 적용 완료, 실기기 확인 필요 |
| OutputDropdown 스트로크 박스 렌더링 | **유저 미확인** | `.fixedSize()` + `.overlay` 조합, 실기기 확인 필요 |

---

## 코드베이스 주요 설계 결정

### etcOutputIdx 저장 구조
```swift
// RuleEngine.swift — RulesData
init(from decoder: Decoder) throws {
    ...
    etcOutputIdx = (try? c.decode(Int.self, forKey: .etcOutputIdx)) ?? 0
    // 기존 저장파일에 키 없으면 0으로 폴백
}
```

### 출력모드 재실행 시 리셋
```swift
// OrganizerViewModel.loadSettings()
categories   = saved.categories.map { var c = $0; c.outputIdx = 0; return c }
etcOutputIdx = 0
```

### 창 리사이즈 차단
```swift
// ResizeLockCoordinator: NSWindowDelegate
func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    return sender.frame.size  // 현재 크기 반환 → 드래그 차단
}
// 프로그래밍적 setFrame(애니메이션)은 이 delegate 미경유
```

### 빈 폴더 삭제 (되돌리기)
```swift
// UndoHistory.undo()
var createdFolders = Set(entry.moves.map { $0.to.deletingLastPathComponent().path })
// 파일 복원 후...
for folderPath in createdFolders {
    let contents = (try? fm.contentsOfDirectory(atPath: folderPath)) ?? []
    if contents.isEmpty { try? fm.removeItem(at: folderURL) }
}
```

### 파일명 편집 — 선택 항목 기준 순번
```swift
// RenameViewModel.previewName()
guard item.isSelected else { return item.displayName }
let selectedItems = items.filter { $0.isSelected }
let selectedIndex = selectedItems.firstIndex(where: { $0.id == item.id }) ?? index
// selectedIndex 기준으로 번호 생성
```

---

## 파일 변경 목록

```
FileSecretary/
├── Core/
│   ├── RuleEngine.swift          RulesData에 etcOutputIdx 추가, custom decoder
│   ├── FileOrganizer.swift       organize()에 etcOutputIdx 파라미터 추가
│   ├── OrganizerViewModel.swift  etcOutputIdx 상태, 로드/저장, runOrganize 전달
│   ├── UndoHistory.swift         되돌리기 후 빈 폴더 삭제
│   └── FileRenamer.swift         RenameItem에 isSelected 추가
├── ContentView.swift             창 크기 820×640, ResizeLockCoordinator, WindowFinder 수정
└── Views/
    ├── CategoryListView.swift    레이아웃 순서, 버튼 통일, 텍스트 수정, EtcCategoryRow 드롭다운
    ├── CategoryCardView.swift    OutputDropdown private 제거, 스트로크 박스
    ├── LeftPanelView.swift       패널 너비 240px
    ├── DiskStatusBar.swift       좌정렬, 아이템 패딩 32px
    ├── FileRenameView.swift      컬럼 헤더 체크박스, 전체선택, previewName/apply 수정
    └── RenameRowView.swift       체크박스, 동일 너비 컬럼, 화살표 가운데
```

---

## 다음 개발 시 참고사항

- **OutputDropdown 스트로크 박스**: `.fixedSize()` + `.overlay` 조합으로 Menu에 적용. label 내부 `.background()`는 borderlessButton이 무시하므로 사용 금지
- **창 리사이즈 차단**: `ResizeLockCoordinator`가 window delegate로 설치됨. 추후 window delegate가 필요한 기능 추가 시 forwardingTarget 체인 활용
- **etcOutputIdx 재실행 리셋**: 의도적 설계. 출력폴더가 세션마다 다를 수 있어 저장하지 않음
- **체크박스 선택 로직**: 선택 항목 기준 순번 재계산 — `items.filter { $0.isSelected }`로 인덱스 계산
