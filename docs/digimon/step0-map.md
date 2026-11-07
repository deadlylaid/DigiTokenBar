# 0단계: PokeTokenBar 구조 정리 (디지몬판 시작점)

정리일: 2026-11-08 · 기준 커밋: upstream `38e3e55` (fix(login): register the app directly at login #474)

## 한 줄 결론

토큰 집계와 포켓몬 동반자가 **함수 두 개로만** 이어져 있다. 그래서 동반자 쪽만 디지몬으로 갈아끼우면 된다.

## 저장소 상태

- 비공개 저장소: https://github.com/deadlylaid/digimon-tokenbar
  - GitHub에서는 공개 저장소의 포크를 비공개로 만들 수 없다. 그래서 원본 기록을 통째로 옮긴 새 비공개 저장소로 만들었다.
- 원격 저장소
  - `origin` = 우리 비공개 저장소
  - `upstream` = 원본 chattymin/PokeTokenBar. 받기만 되고 올리기는 막아뒀다(`DISABLE`).
  - 원본 업데이트 받기: `git fetch upstream && git merge upstream/main`
- 빌드: `swift build` 성공 (이 맥의 Command Line Tools, Swift 6.2.3, 약 70초)
- 테스트: (아래 [테스트 결과](#테스트-결과))

## 구조 한 장

```
UsageStore (사용량 읽기: 14개 도구, 5시간·주간 한도, 캐시)
   │  PokeTokenBarApp.updateCompanion() / onStoreRefreshed()  ← 새로고침마다 호출
   ▼
CompanionStore.update(todayTokensByProvider:, todayDate:, monthTotal:,
                      burnTier:, limitWarning:, hasUsageData:, timeSinceLastUsage:)
CompanionStore.grantCandies(from: candyEligibleWindows, limitsReady:)   ← 한도 채운 보상
   │
   ▼
화면: CompanionView(팝오버 동반자), FloatingPetPanel(바탕화면 펫), MenuBarContent(메뉴바),
      PopoverView, ShopView, BagView, SettingsView 일부
```

- 연결 지점은 `Sources/PokeTokenBar/PokeTokenBarApp.swift`의 `updateCompanion()`과 `onStoreRefreshed()` 두 곳이다.
- 디지몬 엔진이 같은 입력을 받게 만들면 토큰 집계 쪽은 손대지 않아도 된다.

## 재사용 / 교체 / 나중

| 분류 | 파일 | 메모 |
|---|---|---|
| **그대로 재사용** | `Core/` 사용량 쪽 (LocalUsageReader, UsageStore, 각 도구 Provider, OAuth·SessionKey 한도, LocalUsageCache, ModelPricing, BinaryLocator 등) | 약 1만 줄. 포켓몬 관련 코드가 하나도 없다. 14개 도구 지원과 테스트를 그대로 가져온다. |
| 그대로 재사용 | StatusItemMenu, SettingsView 대부분, UsageRecapView, ActivityHeatmap 등 사용량 화면 | 동반자와 상관없는 부분 |
| **떼어서 재사용** | `CompanionStore.update()` 안의 사용량 장부 | 설치 시점 기준선(과거 사용량은 안 셈), 도구별 오늘 사용량, 날짜 변경, 오래된 데이터 무시. 포켓몬과 상관없고 까다로운 예외 처리가 다 들어 있다. 디지몬 엔진의 입력으로 쓴다. |
| 떼어서 재사용 | SaveTransfer, SaveSnapshots | 저장, 스냅샷, 내보내기 구조. 내용만 디지몬으로 바꾼다. |
| 떼어서 재사용 | SpriteLoader / SpriteStore의 "받아서 저장" 방식 | 원칙 8번(그림은 처음 켤 때 받기)과 같은 방식이다. 주소만 PokéAPI에서 Wikimon으로 바꾼다. |
| **교체** | CompanionStore 나머지(부화·진화·성격·이로치), CompanionModel, PokeAPIClient, PokemonForm, PokemonProfile, PokemonNameLocalization, PokemonNameLabel | 디지몬 데이터 모델과 진화 엔진으로 바꾼다. |
| 교체 | CompanionView, FloatingPetPanel의 그림 부분, 메뉴바 그림 | 별도 테스트 앱(이 저장소 밖)에서 다듬은 움직임 코드를 옮긴다. |
| **나중 (MVP 이후)** | ShopView, BagView, 상점 가격, 사탕 | 기준 문서에서 상점은 MVP 이후로 정했다. |
| **빼거나 반대로** | `grantCandies` (한도를 채우면 사탕 보상) | **"토큰 낭비 유도 금지" 원칙과 충돌한다.** 한도를 채우면 보상을 주는 구조라서다. 빼거나, 반대로 "한도 초과 = 돌봄 실수" 갈래 조건으로 쓴다. |

## 진화 조건에 쓸 수 있는 입력 (이미 있음)

| 입력 | 쓸 수 있는 곳 |
|---|---|
| `todayTokensByProvider` (도구별 오늘 토큰) | 경험치. 주로 쓴 도구에 따라 백신·데이터·바이러스 갈래 |
| `todayDate` + 장부의 날짜 기록 | 활동 일수 |
| `burnTier` (쓰는 속도) | 표시 상태. 너무 몰아 쓰면 지친 모습 등 |
| `limitWarning`, `candyEligibleWindows` (한도 경고, 한도를 채운 기록) | "한도 초과 = 돌봄 실수" 갈래 |
| `timeSinceLastUsage` (마지막 사용 뒤 지난 시간) | 잠자기 |
| 현재 시각 | 새벽 코딩이면 바이러스 계열 |

## 포크하면서 주의할 것

- **원본 파일은 최소한만 고친다.** 디지몬 코드는 새 폴더(예: `Sources/PokeTokenBar/Digimon/`)에 모은다. 그래야 `upstream` 업데이트(새 도구 지원, 로그 형식 변경 대응)를 쉽게 받는다.
- **원본의 개발 규칙이 같이 따라왔다.** `CLAUDE.md`, `AGENTS.md`, `.agents/skills/prepare-pr`가 있고 "PR·커밋은 영어", 릴리스 절차 같은 규칙이 들어 있다. 우리에게 맞게 정리해야 한다.
- 원본에는 한국어 코드 주석이 많다. 읽기에는 편하다.
- 라이선스는 MIT다. `LICENSE`를 그대로 두고, 공개할 때 원작자 표기를 남긴다.

## 실행 확인

- **2026-11-08:** 디버그 빌드(`.build/debug/PokeTokenBar`)를 `PTB_STATE_DIR=<임시 폴더>`로 켰다.
- 켜자마자 그날 쓴 Claude Code 토큰을 읽었다. 그리고 동반자 저장 파일(`companion-state.json`)에 설치 기준선(`installBaselineSet: true`)을 잡았다.
- **사용량 → 동반자 연결 지점이 실제로 동작하는 걸 확인했다.** 키체인 암호 창은 뜨지 않았다.
- **주의: `PTB_STATE_DIR`로도 다 격리되지는 않는다.** 아래 두 곳에는 여전히 기록된다.
  - `~/Library/Application Support/PokeTokenBar/base-index.json` (PokéAPI 목록 캐시)
  - UserDefaults 도메인 `PokeTokenBar` (날짜별 토큰 기록, 난이도 설정)
- **디지몬판에서 할 일:**
  - 번들 ID, 앱 이름, 저장 폴더 이름, UserDefaults 도메인을 바꾼다. 그래야 진짜 PokeTokenBar를 같이 깔아도 데이터가 섞이지 않는다.
  - 개발용 격리 설정이 캐시와 설정까지 덮게 만든다.

## 테스트 결과 (원본 기준점)

- **2026-11-08, 처음 시도:** 실행하지 못했다. 이 맥에 Xcode 없이 Command Line Tools만 있어서 `no such module 'XCTest'`가 났다.
- **2026-11-09, 기준점 측정:** macOS 27.2, Xcode 27.2(Swift 6.4.2)에서 디지몬 코드를 넣기 전 원본 그대로 돌렸다.

| 실행 | 결과 |
|---|---|
| 전체 한 번에 (`swift test`) | 테스트 1,897개 중 25개 건너뜀, **확인 실패 8건**, 약 8분 |
| 묶음별로 (184개 묶음, 묶음마다 4분 제한) | **182개 묶음 통과** (약 1,890개). 문제 2개는 아래 |

| 문제 테스트 | 증상 | 원인 판단 |
|---|---|---|
| `IndividualPickerRenderingTests.testMountedSingleAndMultipleIndividuals` | 확인 실패 2건. 화면에서 선택 메뉴(`NSPopUpButton`)를 0개 찾음(기대값 1) | macOS 27 / Xcode 27에서 SwiftUI가 메뉴를 그리는 내부 방식이 바뀐 것으로 보인다. 원본 코드는 그대로다. |
| `DexBackNavigationTests` (6개 중 3개 실패: `testBackFromDetailReturnsToThePageOfThatSpecies`, `testBackToTheLogLeavesTheGridOnItsFirstPage`, `testReturnPageIsUsedOnlyOnce`) | 확인 실패 6건. 그린 화면을 macOS 글자 인식(Vision)으로 읽는데 "Back" 글자를 찾지 못한다. 가끔은 글자 인식 단계에서 CPU 0%로 멈춰서 끝나지 않는다(두 번 그랬다). | macOS 27에서 뒤로가기 버튼이 다르게 그려지는 것으로 보인다. 원본 코드는 그대로다. |

- 전체 실행의 확인 실패 8건 = 위 2건 + 6건. 원인이 모두 확인됐다.

### 포켓몬 전용 테스트 정리 (2026-11-09)

포켓몬에만 있는 기능의 테스트를 지웠다. 지운 건 git 기록에 남아 있다.

- **통째로 지운 파일 41개:** 도감, 폼, 언노운, 메타몽, 이로치, 성격·민트, 사탕, 상점, 알 등급, 기도, 포켓몬 이름, 포켓몬 그림 로더, 난이도, 대표 포켓몬, 위 실패 테스트 2개 등
- **일부만 지운 파일 2개:**
  - `CompanionTests.swift`: 남긴 것은 사용량 장부 9개, 저장 파일 깨짐 백업 1개, 앱 언어·날짜 표시 묶음이다. 다른 테스트가 쓰는 공용 도우미도 남겼다.
  - `UsageRecapTests.swift`: 언노운 글자 테스트 1개만 지웠다.
- **남긴 것:**
  - 사용량·한도·각 AI 도구 테스트 전부
  - 3·4단계에서 디지몬용으로 고쳐 쓸 기반 테스트: 저장·백업, 바탕화면 펫 창, 팝오버 이동, 동반자 표시 상태, 메뉴바 그림, 성능

| | 지우기 전 | 지운 뒤 | 차이 |
|---|---|---|---|
| 테스트 수 | 1,897 | 1,342 (원본 1,324 + 디지몬 18) | −555 |
| 확인 실패 | 8 | **0** | 기준점이 깨끗해졌다 |
| 테스트 실행 시간 (전체 한 번에) | 483초 | **313초** | **−35%** |
| 테스트 빌드 시간 (처음부터) | 38초 | 32초 | −16% |
| 멈춤 위험 | 도감 뒤로가기 테스트가 가끔 끝나지 않음 | 없음 | |

- **이제 테스트가 하나라도 실패하면 우리 변경 때문이다.**
- 남은 시간의 절반 이상(약 168초)은 `UsageStoreTests` 한 묶음이 차지한다.
- **둘 다 포켓몬 화면 테스트**다. 디지몬판에서 교체할 부분이라 디지몬 작업에는 영향이 없다.
- **앞으로 테스트를 돌렸을 때 위 4개 테스트만 실패하면 원래 상태다.** 다른 테스트가 실패하면 우리 변경 때문이다.
- `DexBackNavigationTests`가 멈추면 전체 실행이 끝나지 않는다. 그럴 땐 `--skip DexBackNavigationTests`로 빼고 돌린다.
- 다시 재는 방법: 묶음별 실행 도우미 `.build/run_baseline.py`를 썼다(로컬 전용, 커밋 안 함). 전체는 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`로 돌린다.

## 다음: 1단계

1단계도 끝났다. [1단계 문서](step1-evolution-data.md)와 [2단계 문서](step2-engine-design.md)를 보면 된다.
