# 릴리스 프로세스

DigiTokenBar 배포판(GitHub Release 의 `DigiTokenBar.zip`)을 내는 런북이다. 기계적 단계는 `scripts/release.sh` 가
자동화하고, 내용 판단이 필요한 부분은 아래 체크리스트로 검토한다. 실행 세부와 함정은
`docs/reference/release-workflow.md`.

원본 PokeTokenBar 와 다른 점:

- **Homebrew cask 가 없다.** 사용자는 릴리스에서 zip 을 받는다. 앱의 업데이트 알림은 릴리스 페이지를 연다
  (`AppIdentity.homebrewCask = nil` — brew 를 묻지 않는다).
- **랜딩 페이지(GitHub Pages)가 없다.** README(en/ko/ja)가 소개 페이지다.
- **스크린샷을 저장소에 두지 않는다.** 디지몬 그림은 우리 것이 아니다. 앱도 그림을 담지 않고 실행 중에
  Wikimon 에서 받는다. `assets/` 에는 앱 아이콘만 있다.
- **공증(notarization)을 받지 않는다.** Apple Developer ID 가 없는 무료 팬 프로젝트라, 사용자는 처음 열 때
  "개발자를 확인할 수 없음"을 한 번 넘어야 한다(시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기). README 와
  릴리스 노트의 Install 줄이 이를 안내한다.

## 한 줄 배포

```bash
# 템플릿을 복사한 뒤 실제 변경사항과 Contributors를 작성한다(필수).
cp docs/reference/release-notes-template.md /tmp/notes.md
# /tmp/contributors.txt: 포함된 PR에서 확인한 GitHub handle을 한 줄에 하나씩 작성한다.
# 외부 기여자가 없는 릴리스만 빈 파일을 사용하며, 노트에도 없음을 명시한다.

PTB_NOTES_FILE=/tmp/notes.md PTB_CONTRIBUTORS_FILE=/tmp/contributors.txt ./scripts/release.sh 0.1.1
```

`scripts/release.sh <version>` 가 순서대로 수행:

0. **노트·Contributors 검사** — 필수 섹션, zip 설치·첫 실행·업그레이드 안내, Homebrew 안내 없음, 확인한 기여자
   목록 대조. 누락 시 빌드·앱 교체·push 전에 중단.
1. **test-gate** (`./scripts/test-gate.sh`) — 전체 테스트 + 로직 커버리지. 실패 시 중단.
2. **문서 검토 + 버전 확인** — 아래 자동 경고. 경고가 있으면 터미널에서는 진행 여부를 묻고, 터미널이 아니면
   중단한다. 같은 태그·릴리스가 이미 있거나 버전이 직전 릴리스보다 높지 않으면 중단.
3. **서명 신원 게이트** — `DigiTokenBar Local` 인증서가 있고 고정 지문(`EXPECTED_LEAF`)과 같은지.
4. **VERSION 범프** (`scripts/build-app.sh`, 아직 미커밋).
5. **빌드 + zip** (`build/DigiTokenBar.zip`) — 빌드 버전 일치, universal(arm64 + x86_64), `DigiTokenBar Local`
   서명을 확인한다. **push 전 검증**(실패해도 범프 미커밋이라 origin/main 무손상). 이 단계에서 `/Applications`
   의 앱도 새 빌드로 바뀐다.
6. **커밋 + push** — 범프가 있으면 `release: bump version to X.Y.Z` 커밋. `build-app.sh` 가 이미 그 버전이면
   (첫 릴리스 0.1.0) 커밋 없이 HEAD 를 push 한다.
7. **GitHub Release** — `vX.Y.Z` 태그를 지금 HEAD 에 만들고 zip 을 붙인다(`PTB_NOTES_FILE` 원문 사용).

> `main` 브랜치에서만 실행(스크립트가 가드). 비-main 에서 실행 시 즉시 중단.

검토만 하려면: `./scripts/release.sh --check-only`

노트만 검사하려면: `python3 scripts/release-metadata.py check-notes /tmp/notes.md /tmp/contributors.txt`

스크립트 테스트: `python3 -m unittest discover -s scripts/tests -p 'test_*.py'`

## 문서 검토 (자동 경고)

`release.sh` 2단계가 잡는 것:

- README 에 정적 버전 배지, 제거된 도구(`ccusage`) 흔적.
- README.md / .ko / .ja 중 zip 설치 안내(`DigiTokenBar.zip`, `releases/latest` 링크)가 없는 것, 설치 안내에 버전
  번호를 박은 것, Homebrew cask 안내가 남은 것.
- `assets/` 에 앱 아이콘 말고 다른 파일(스크린샷 등)이 있는 것.
- 직전 DigiTokenBar 릴리스 이후 `feat` 커밋이 있는데 README 가 그대로인 것, README 가 세 언어 중 일부만 바뀐 것.
  "직전 릴리스"는 우리 태그만 본다. 저장소에 남은 원본의 v2.x 태그는 갈라진 지점 이전이라 건너뛴다.

수동 체크리스트 — **기능/동작이 바뀐 릴리스면 반드시 갱신**:

- [ ] **README.md / README.ko.md / README.ja.md** — 기능 목록, 설치, 요구사항, 데이터 출처. 3개 언어 동시.
- [ ] **릴리스 노트** — New / Fixed / Other / Contributors, 템플릿의 Install / Upgrade 줄 그대로.

## 릴리스 노트와 기여자

- 원본 [v2.5.3](https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.3)의 모양을 따라 영어
  `New / Fixed / Other / Contributors`와 `Install / Upgrade` 안내를 유지한다. Install / Upgrade 줄은
  `docs/reference/release-notes-template.md` 의 것을 그대로 쓴다(검사기가 확인한다).
- 기능은 사용자에게 달라지는 동작을 설명하고 PR 이 있으면 PR 번호와 작성자 `@handle`을 연결한다.
  변경 없는 분류는 `None.`으로 남긴다. 문서 변경은 `Other`에 정리한다.
- **직전 공개 릴리스 태그부터 배포 대상 커밋까지** 포함된 PR을 전수 확인한다. 날짜 검색만으로
  대체하지 않는다. PR 작성자와 확인 가능한 실제 공동기여자의 GitHub handle을 수집한다.
  저장소 소유자(`deadlylaid`)와 봇은 제외한다. 원본을 다시 합친(upstream merge) 릴리스면, 합친 원본 PR 의
  작성자도 확인해 넣는다.
- 확인한 목록을 `PTB_CONTRIBUTORS_FILE`에 한 줄 한 handle로 저장하고 노트 Contributors와 대조한다.
  검사기는 이 목록 및 변경 설명에 등장한 외부 `@handle`의 누락을 차단한다. 목록 자체의 완전성은
  위 PR·커밋 대조로 확인해야 한다. 이전 릴리스 목록을 복사하지 않는다.
- 외부 기여자가 없을 때만 빈 목록 파일과 `No external contributors in this release.`를 사용한다.
  기여자가 있으면 `@alice · @bob` 목록 아래 `Thank you all.`을 적는다.

## 커밋 공동작성자

릴리스 커밋에는 기본적으로 `Co-Authored-By`를 붙이지 않는다. 실제 해당 커밋에 공동작업한
참여자가 확인될 때만 `PTB_COAUTHORS_FILE`에 한 줄당 `Name <email>`로 작성해 전달한다.
특정 AI 이름은 고정하지 않으며, 현재 도구나 이전 커밋만 보고 추측하지 않는다.
전체 릴리스의 Contributors와 릴리스 준비 커밋의 공동작성자는 별도로 판정한다.

```bash
PTB_NOTES_FILE=/tmp/notes.md PTB_CONTRIBUTORS_FILE=/tmp/contributors.txt \
  PTB_COAUTHORS_FILE=/tmp/coauthors.txt ./scripts/release.sh 0.1.1
```

## E2E 스모크 (선택 — GUI 세션 필요)

```bash
./scripts/e2e.sh
```

실제 앱 번들로 빌드→기동→데이터 파이프라인(스냅샷 갱신·구조 검증·AppLog)→메뉴바
status item(AX)→팝오버 오픈(AXPress)까지 7개 체크. 5단계는 터미널에 손쉬운 사용
(Accessibility) 권한 필요 — 미허용이면 해당 단계만 SKIP. release.sh 에 포함하지 않는
이유: GUI 세션·권한 의존이라 헤드리스 실행이 깨질 수 있음. 릴리스 전 수동 1회 권장.

## 자동으로 갱신되는 것 (수동 불필요)

- 인앱 업데이트 알림 — `deadlylaid/DigiTokenBar` 의 `releases/latest` 기준. 누르면 릴리스 페이지가 열린다.

## 배포 후 검증

사용자가 받는 것과 같은 파일로 확인한다.

```bash
gh release download vX.Y.Z --repo deadlylaid/DigiTokenBar --pattern DigiTokenBar.zip --dir <임시 폴더>
ditto -x -k <임시 폴더>/DigiTokenBar.zip <임시 폴더>
codesign -dv --verbose=2 <임시 폴더>/DigiTokenBar.app   # Authority=DigiTokenBar Local
lipo -archs <임시 폴더>/DigiTokenBar.app/Contents/MacOS/DigiTokenBar   # x86_64 arm64
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" <임시 폴더>/DigiTokenBar.app/Contents/Info.plist
```

그다음 브라우저로 받은 zip(격리 표시가 붙는다)을 풀어 한 번 열어 보고, "그래도 열기"로 열리는지 본다.

## 서명

릴리스 빌드는 이 머신의 `DigiTokenBar Local` 자체서명 인증서로 서명된다
(`scripts/create-signing-cert.sh` 로 생성, keychain 에만 존재 — 레포 미커밋).
- designated requirement 가 버전 간 고정 → 사용자의 Keychain "항상 허용"이 업데이트 후에도 유지.
- 자체서명이라 Gatekeeper 는 통과하지 못한다(공증은 Apple Developer ID 가 있어야 한다). 첫 실행 안내가 필요한 이유다.
- 인증서를 분실/재생성하면 DR 이 바뀌어 전 사용자 재프롬프트 — 재생성 금지(스크립트가 지문으로 가드).
