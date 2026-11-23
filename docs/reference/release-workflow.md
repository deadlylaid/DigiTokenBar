---
summary: "릴리스 실행 절차 — README 갱신 의무, 노트·기여자 준비, release.sh 게이트의 함정, 배포 후 검증."
read_when:
  - 버전을 배포할 때 (자연어 트리거 포함: "배포해줘", "릴리스 올려줘", "패치 배포")
  - release.sh 가 문서 경고·서명·버전 게이트로 중단됐을 때
  - 기능을 바꿔 README(en/ko/ja)를 갱신해야 할 때
---

# 릴리스 실행 절차

버전 결정 규칙과 트리거는 `CLAUDE.md` §릴리스에 있다. 이 문서는 그 다음의 *실행 세부*를 담는다.
체크리스트 원본은 `RELEASE.md`.

DigiTokenBar 는 GitHub Release 에 `DigiTokenBar.zip` 을 올리는 것으로 배포한다. 원본 PokeTokenBar 의
Homebrew cask, 랜딩 페이지(gh-pages), README 스크린샷은 없다 — cask·랜딩을 만들지 않았고, 디지몬 그림은
우리 것이 아니라 저장소에 넣지 않는다.

## 1. 문서 갱신 (매 릴리스 필수 — "할까요?" 묻지 말고 무조건 한다)

`./scripts/release.sh --check-only` 로 경고를 확인한 뒤 아래를 반영한다.

- **README.md/ko/ja**: 기능 목록·how-it-works·설치·요구사항·데이터 출처. 세 언어를 함께 고친다.
- 설치 안내는 버전 번호 없이 `releases/latest` 를 가리킨다(릴리스마다 낡지 않게).
- 화면 이미지는 넣지 않는다. 화면을 보여 줘야 하면 글로 설명한다.

### 게이트의 함정

- `release.sh` 문서검토는 *커밋된* 상태를 비교한다 → README 를 고쳤으면 먼저 커밋한다. 릴리스 커밋에는 이미
  스테이징된 다른 변경도 함께 담기므로 대상도 확인한다.
- 경고가 있으면 터미널에서는 y/N 을 묻고, 터미널이 아닌 곳(에이전트의 셸 등)에서는 바로 중단한다. 에이전트가
  실행할 때는 경고를 고쳐서 없앤 뒤 실행한다.
- "직전 릴리스"는 우리 태그만 센다. 저장소에는 원본의 v2.x 태그가 남아 있지만, 우리 첫 커밋(갈라진 지점
  `38e3e55` 다음)을 품지 않으므로 건너뛴다. 원본을 다시 합쳐도 마찬가지다.
- 첫 릴리스처럼 `build-app.sh` 의 VERSION 이 이미 배포할 버전이면 범프 커밋을 만들지 않고 HEAD 를 배포한다.

## 2. 실행

먼저 `RELEASE.md`의 릴리스 노트·기여자 절차에 따라 준비한다.

- `release-notes-template.md`를 복사하고 영어 New / Fixed / Other / Contributors 를 작성한다.
  Install / Upgrade 줄은 템플릿 그대로 둔다(zip 설치, "Open Anyway", `xattr` 명령, 업그레이드 방법).
  필수 섹션을 지우거나 `Release vX.Y.Z` 한 줄로 대체하지 않는다.
- 직전 공개 릴리스 태그부터 배포 대상까지의 PR·직접 커밋을 확인해 외부 기여자 목록을 만든다.
  PR 작성자와 실제 공동기여자를 빠짐없이 확인하고 `PTB_CONTRIBUTORS_FILE`과 노트의 Contributors를 맞춘다.
  기존 릴리스 목록 재사용이나 날짜만으로 범위를 정하는 방식은 쓰지 않는다.
- 실제 공동작업이 확인된 릴리스 준비 커밋만 `PTB_COAUTHORS_FILE`에 참여자의 이름·이메일을 지정한다.
  기본은 없음이며 Claude/Codex 등 특정 이름을 자동으로 붙이지 않는다.
- 노트 원문과 기여자 목록 검사를 마친 뒤 적용 버전과 노트 요약을 사용자에게 보여준다.

그 다음 반드시 `main` 브랜치에서:

```bash
PTB_NOTES_FILE=/tmp/notes.md PTB_CONTRIBUTORS_FILE=/tmp/contributors.txt ./scripts/release.sh <version>
```

스크립트가 노트·Contributors 검증 → test-gate → 문서검토·버전 확인 → 서명 신원 → 범프 → 빌드검증 →
커밋·push → GitHub Release 를 순서대로 수행한다. 빌드 단계에서 기존 로컬 앱 종료·교체도 수행한다.
노트나 기여자가 누락되면 앱 교체·push 전에 중단하며, 게시에는 검증한 노트 파일을 그대로 사용한다.
push 는 샌드박스 밖 네트워크가 필요하다.

## 3. 검증

`RELEASE.md` §배포 후 검증대로 **릴리스에서 받은 zip** 을 풀어 서명(`Authority=DigiTokenBar Local`),
아키텍처(`x86_64 arm64`), 버전을 확인하고, 브라우저로 받은 zip 을 한 번 열어 첫 실행 안내대로 열리는지 본다.
이전 버전 앱이 깔린 Mac 이 있으면 그 앱이 새 버전을 알리고 릴리스 페이지를 여는지도 본다.
