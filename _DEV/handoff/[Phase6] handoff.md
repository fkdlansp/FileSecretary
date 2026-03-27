# FileSecretary — 개발 핸드오프

작성일: 2026-03-27

---

## 현재 빌드 상태

**정상 빌드 · 동작 확인 완료.**
Phase 6 UI/UX 개선 및 버그 수정 완료. 컴파일 에러 없음.

---

## 이번 세션에서 완료한 작업

### 1. DiskStatusBar — 4개 이상 시 2줄 표시

- 볼륨 1~3번: 첫 번째 줄
- 볼륨 4번~: 두 번째 줄 (수직 Divider 구분)
- 횡스크롤 제거 → 각 줄 끝 `Spacer()`로 왼쪽 정렬
- 각 줄 높이 78px 고정, 2줄일 때 자동으로 156px

### 2. 기타(미분류) 파일 처리 — 3가지 선택지

**변경 전:** "기타로 이동" / "건너뛰기" 2개 버튼

**변경 후:** 3가지 선택지 (`UncategorizedResolution` enum 추가)
- `moveToMain` — 메인 출력 폴더(`outputFolders[0]`)의 기타 폴더로 이동 (출력폴더 없으면 대상폴더)
- `leaveInPlace` — 해당 폴더에 그대로 남기기 (건너뜀)
- `moveToLocalEtc` — 해당 대상 폴더 안에 기타 폴더 만들어서 이동

출력폴더 미등록 시 `moveToMain` 버튼 자체 숨김.

### 3. 멀티폴더 되돌리기 버그 수정

**버그:** 폴더마다 `undoHistory.push()` 개별 호출 → undo 1번에 마지막 폴더만 복원

**수정:** `combinedMoved/Skipped/Errors` 배열로 폴더별 결과 합산 → 루프 종료 후 `OrganizeResult` 1개로 조립 → `undoHistory.push(combined)` 1회 호출

### 4. 멀티폴더 로그 버그 수정

**버그:** 폴더마다 `logOrganizeResult()` 개별 호출 → "정리 시작/완료" 헤더 N번 반복

**수정:** 합산 결과로 1회만 로그 기록, `targetFolders` 전체 목록 전달

### 5. organize() 호출 시 security-scoped URL 수정

**버그:** `organize(targetFolder: folder, outputFolders: outputs)` — 원본 URL 사용

**수정:** `organize(targetFolder: secureFolder, outputFolders: secureOutputs)` — 북마크 복원 URL 사용 (샌드박스 접근 권한 정확히 전달)

### 6. 다중 출력폴더 시 폴더명 넘버링 제거

- `outputFolders.count > 1`이면 `cat.folderName` (`01_이미지`) 대신 `cat.name` (`이미지`) 사용
- 단일/출력폴더 없음: 기존 `01_이름` 형식 유지

### 7. 출력폴더 제한 제거 (4개 → 무제한)

- `addOutputFolder()`: `guard count < 4` 제거
- `LeftPanelView`: 드롭 guard, AddFolderButton disabled 조건 제거, 헤더 "최대 4개" 삭제
- `OutputFolderRow`: `palette`(8색) + 알파벳 라벨(A-P, 이후 숫자) 자동 확장
- `OutputDropdown`, `outputFolderLabel`: 동일하게 확장 처리
- **팔레트 단일 관리:** `CategoryCardView.palette` 정적 배열 → `LeftPanelView`가 참조

### 8. 일괄 처리 — 체크박스 방식

**기타 다이얼로그 (`UncategorizedDialog`)**
- "이 대상 폴더의 이후 미분류 파일에 모두 적용" 체크박스 추가
- 체크 O → 이번 정리에서 같은 대상 폴더 내 미분류 파일 전체에 자동 적용
- 체크 X → 매번 다이얼로그 표시

**충돌 다이얼로그 (`CategoryConflictDialog`)**
- "같은 카테고리 조합의 이후 파일에 모두 적용" 체크박스 추가
- 충돌 조합 키: `Set<String>` (category ID 집합) — 조합이 다르면 별도 캐시
- 폴더가 바뀌면 캐시 리셋 (폴더1 설정 ≠ 폴더2 설정)

**구현 방식:**
- `pendingUncategorizedCompletion: ((UncategorizedResolution, Bool) -> Void)?`
- `pendingConflictCompletion: ((ConflictResolution, Bool) -> Void)?`
- `askUncategorized()` → `(UncategorizedResolution, Bool)` 반환
- `askConflict()` → `(ConflictResolution, Bool)` 반환
- `runOrganize()` 내 `cachedConflicts: [Set<String>: ConflictResolution]`, `cachedUncategorized: UncategorizedResolution?` — 폴더 루프 안에서 선언 (반복마다 리셋)

### 9. 카테고리 카드 — 출력폴더 색상 표시

- `CategoryCardView.outputColor`: `outputIdx > 0`이면 팔레트 색 반환, 0이면 `nil`
- 카드 배경에 팔레트 색 옅은 틴트 (opacity 0.18)
- 카드 왼쪽 4px 색상 바 (`UnevenRoundedRectangle` — 왼쪽만 라운드)
- 개별 모드 또는 출력폴더 미지정 → 색 없음

### 10. 원클릭 다운로드 / 도구 → 우측 사이드바 이동

**변경 전:** LeftPanelView 하단에 "원 클릭 다운로드 폴더 정리" + "도구" 섹션 존재

**변경 후:**
- LeftPanelView에서 두 섹션 완전 제거 → 좌측패널 길이 대폭 단축
- CategoryListView 하단 (+ 카테고리 추가 ~ 액션바 사이)에 수평 2분할로 배치
  - 좌: 원 클릭 다운로드 (지금 정리 버튼)
  - 우: 도구 (프리셋 저장/불러오기, 로그 폴더)

### 11. 파일명 편집 컨트롤바 레이아웃 개선

**변경 전:** 4개 기능을 1줄에 구겨넣기 → 글자 찌그러짐

**변경 후:** 4컬럼 수평 배치, 각 컬럼 = **라벨(위) + 컨트롤(아래) + 설명(아래)**
- 번호 자릿수 | 시작 번호 | 공통 이름 | 통일 방식
- 시작 번호 아래: "비우면 번호 없이 저장"
- 공통 이름 아래: "비우면 원본 파일명 유지"
- 통일 방식 아래: 현재 선택에 따른 포맷 미리보기 ("번호_통일명.확장자" 등)

### 12. 화면B 기본 크기 조정

- 확장 애니메이션 타겟: `820×580` → `730×570`
- 최소 크기: `720×500` → `730×570`

### 13. ActionButtonStyle — 최소 너비 통일

- `minWidth: CGFloat = 76` 기본값 추가
- "적용", "초기화", "제외 목록" 등 짧은 버튼이 자동으로 최소 폭 확보

---

## 현재 알려진 미확인 사항

| 항목 | 상태 | 비고 |
|------|------|------|
| 메뉴바 항목 실제 동작 | **유저 미확인** | static ref 패턴 적용 후 테스트 필요 |
| ExFAT 외장하드 디스크 사용량 표시 | **유저 미확인** | 폴백 로직 적용 완료, 실기기 확인 필요 |
| 되돌리기 버튼 미생성 케이스 | **간헐적** | security-scoped URL 수정으로 개선 예상, 재현 시 추가 디버깅 필요 |

---

## 코드베이스 주요 설계 결정

### UncategorizedResolution 3-way enum
```swift
enum UncategorizedResolution {
    case moveToMain      // outputFolders[0]/기타 (없으면 targetFolder/기타)
    case leaveInPlace    // 건너뜀
    case moveToLocalEtc  // targetFolder/기타
}
```
`FileOrganizer.organize()` 내 `uncategorizedDest: URL?` override로 목적지 분기.

### 다중 출력폴더 시 넘버링 제거 로직
```swift
// FileOrganizer.organize() 내
let folderName: String
if let cat = chosenCategory {
    folderName = outputFolders.count > 1 ? cat.name : cat.folderName
} else {
    folderName = "기타"
}
```

### 일괄 처리 캐시 구조
```swift
// runOrganize() 폴더 루프 내부에서 선언 → 폴더마다 리셋
var cachedConflicts: [Set<String>: ConflictResolution] = [:]
var cachedUncategorized: UncategorizedResolution? = nil
```
체크박스가 체크된 경우에만 캐시에 저장. 미체크 시 매번 다이얼로그 표시.

### 카테고리 카드 색상 팔레트
```swift
// CategoryCardView.swift
static let palette: [Color] = [.blue, .green, .orange, .purple, .cyan, .pink, .yellow, .indigo]
```
`LeftPanelView.OutputFolderRow`에서 `CategoryCardView.palette` 참조 — 단일 출처.

---

## 파일 구조 요약

```
FileSecretary/
├── FileSecretaryApp.swift
├── ContentView.swift               화면 A/B 전환, 윈도우 크기 730×570
├── Core/
│   ├── OrganizerViewModel.swift    UncategorizedResolution, 일괄캐시, security-scoped URL
│   ├── FileOrganizer.swift         UncategorizedResolution 3-way, 다중출력 넘버링 제거
│   ├── RuleEngine.swift
│   ├── DuplicateResolver.swift
│   ├── FileRenamer.swift
│   ├── UndoHistory.swift
│   ├── LogWriter.swift
│   ├── XLSXExporter.swift
│   ├── DiskMonitor.swift
│   ├── BookmarkManager.swift
│   └── SettingsManager.swift
└── Views/
    ├── DiskStatusBar.swift         2줄 표시 (4개+)
    ├── FileOrganizerView.swift     다이얼로그 applyToAll Bool 추가
    ├── LeftPanelView.swift         원클릭/도구 섹션 제거, 출력폴더 무제한
    ├── CategoryListView.swift      원클릭/도구 섹션 추가, ActionButtonStyle minWidth
    ├── CategoryCardView.swift      출력폴더 색상 바, palette 단일 관리
    ├── CategoryModalView.swift
    ├── DropZoneView.swift
    ├── FileRenameView.swift        컨트롤바 4컬럼 라벨+컨트롤 레이아웃
    ├── RenameRowView.swift
    └── Dialogs/
        ├── DuplicateFileDialog.swift
        ├── UncategorizedDialog.swift   3버튼 + applyToAll 체크박스
        ├── CategoryConflictDialog.swift applyToAll 체크박스
        └── ExcludeListView.swift
```

---

## 다음 개발 시 참고사항

- **테스트 인프라 없음** — 수동 테스트만 가능
- **비재귀 스캔** — `FileOrganizer`는 대상 폴더 직접 하위 파일만 정리
- **출력폴더 무제한** — A-P(16개)까지 알파벳, 이후 숫자 라벨 자동 적용
- **팔레트 단일 출처** — `CategoryCardView.palette` (8색 순환)
- **일괄 적용 캐시** — 체크박스 체크 시에만 캐시 저장, 폴더 변경 시 자동 리셋
- **설정 저장 위치** — `~/Library/Application Support/FileSecretary/user_settings.json`
- **로그/XLSX 저장 위치** — `~/Library/Logs/FileSecretary/log/`, `xlsx/`
