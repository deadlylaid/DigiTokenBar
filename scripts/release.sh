#!/usr/bin/env bash
#
# release.sh — DigiTokenBar 버전 배포 자동화 + README 일관성 검토.
#
# 사용:
#   PTB_NOTES_FILE=/tmp/notes.md PTB_CONTRIBUTORS_FILE=/tmp/contributors.txt ./scripts/release.sh 0.1.0
#   ./scripts/release.sh --check-only     # 문서 일관성 검토만(배포 안 함)
#
# 단계: 0)노트·기여자 검사 1)test-gate 2)문서 검토 3)서명 신원 4)VERSION 범프 5)build+zip
#       6)커밋·push 7)GitHub Release. 각 단계 실패 시 즉시 중단(set -e).
#
# 원본 PokeTokenBar 에 있던 Homebrew cask·랜딩(GitHub Pages)·스크린샷 단계는 없다. DigiTokenBar 는
# cask 와 랜딩이 없고, 디지몬 그림은 우리 것이 아니라서 저장소에 스크린샷을 두지 않는다
# (README: 그림은 앱이 실행 중에 Wikimon 에서 받는다).
#
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="deadlylaid/DigiTokenBar"
APP_NAME="DigiTokenBar"
APP="build/$APP_NAME.app"
ZIP="build/$APP_NAME.zip"
# Homebrew cask (github.com/deadlylaid/homebrew-tap). Step 8 sets its version and sha256 to the new zip.
TAP_REPO="deadlylaid/homebrew-tap"
CASK_PATH="Casks/digitokenbar.rb"
# 원본 PokeTokenBar 에서 갈라진 지점. 이 저장소에는 원본의 v2.x 태그도 남아 있는데, 그 태그들은 우리
# 첫 커밋(갈라진 지점 바로 다음)을 품지 않는다. 원본을 나중에 다시 합쳐도 마찬가지다.
FORK_POINT="${PTB_FORK_POINT:-38e3e5532846d407ae1a80fe15c4e49a0c263d65}"   # 변수는 테스트용

# 직전 DigiTokenBar 릴리스 태그. 없으면(첫 릴리스) 빈 문자열.
last_release_tag() {
  local first tag
  first=$(git rev-list --ancestry-path --reverse "$FORK_POINT"..HEAD | head -1)
  [[ -n "$first" ]] || return 0
  for tag in $(git tag --merged HEAD --list 'v*' --sort=-v:refname); do
    if git merge-base --is-ancestor "$first" "$tag" 2>/dev/null; then echo "$tag"; return 0; fi
  done
}

# ── 문서 일관성 검토 (배포 전 항상 실행) ───────────────────────────────────
# 기계적으로 잡을 수 있는 것만 자동 경고. 내용(기능 설명) 변경 여부는 사람이 체크리스트로 판단.
doc_check() {
  local warn=0 f
  echo "▶ 문서 일관성 검토"
  # 정적 버전 하드코딩(릴리스마다 수동 갱신 필요 → 동적 배지 권장)
  if grep -rnE "img.shields.io/badge/release-v[0-9]" README*.md 2>/dev/null; then
    echo "  ⚠ README 에 정적 버전 배지가 있습니다(동적 github/v/release 배지 권장)."; warn=1
  fi
  # 제거된 의존성/도구 흔적 (필요 시 PATTERN 에 추가)
  for pat in ccusage; do
    if grep -rniq "$pat" README*.md 2>/dev/null; then
      echo "  ⚠ README 에 '$pat' 잔존 — 제거된 항목인지 확인."; warn=1
    fi
  done
  # 설치 안내: 세 언어 README 모두 내려받기(zip)와 최신 릴리스 링크를 안내하고, 버전 번호를 박지 않는다.
  # Homebrew 안내는 우리 cask(deadlylaid/tap/digitokenbar)여야 한다 — 원본 cask 는 다른 앱을 깐다.
  for f in README.md README.ko.md README.ja.md; do
    if ! grep -q "$APP_NAME.zip" "$f" || ! grep -q "github.com/$REPO/releases/latest" "$f"; then
      echo "  ⚠ $f 에 내려받기 설치 안내($APP_NAME.zip, releases/latest 링크)가 없습니다."; warn=1
    fi
    if grep -nE "releases/download/v[0-9]|$APP_NAME[ -]v?[0-9]+\.[0-9]+\.[0-9]+" "$f"; then
      echo "  ⚠ $f 설치 안내에 버전 번호가 박혀 있습니다 — 릴리스마다 낡습니다(releases/latest 로)."; warn=1
    fi
    if ! grep -q "brew install --cask deadlylaid/tap/digitokenbar" "$f"; then
      echo "  ⚠ $f 에 Homebrew 설치 안내(brew install --cask deadlylaid/tap/digitokenbar)가 없습니다."; warn=1
    fi
    if grep -nE "chattymin/tap|poke-token-bar" "$f"; then
      echo "  ⚠ $f 에 원본 PokeTokenBar 의 cask 안내가 있습니다 — 다른 앱을 깝니다."; warn=1
    fi
  done
  # 디지몬 그림(스크린샷)을 저장소에 넣지 않는다 — 앱 아이콘만 둔다.
  local extra_assets
  extra_assets=$(git ls-files assets | grep -v '^assets/AppIcon.icns$' || true)
  if [[ -n "$extra_assets" ]]; then
    echo "  ⚠ assets/ 에 앱 아이콘 말고 다른 파일이 있습니다(디지몬 그림은 저장소에 넣지 않음):"
    echo "$extra_assets" | sed 's/^/       /'
    warn=1
  fi
  # 가격표: 앱이 가격 없는 모델을 만나면 기록에 "Unpriced model: <id>"를 남기고 비용을 "계산 불가"로 보인다.
  # 이 Mac 의 기록에 그런 모델이 있는데 가격표(ModelPricing.swift)에 아직 없으면 경고한다.
  # (2026-11: Fable 5.2·Haiku 5.5 가 수십 번 찍혔는데 기록 한 줄로만 남아 아무도 못 봤다.)
  local applog="$HOME/Library/Logs/$APP_NAME.log" model key unpriced=""
  if [[ -f "$applog" ]]; then
    while read -r model; do
      [[ -n "$model" ]] || continue
      key=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]' | sed -E 's#^(openai|anthropic|google|models)/##')
      grep -qF "\"$key\"" Sources/PokeTokenBar/Core/ModelPricing.swift || unpriced+="$key "
    done < <(grep -ho 'Unpriced model: [^ ]*' "$applog" 2>/dev/null | sed 's/^Unpriced model: //' | sort -u)
  fi
  if [[ -n "$unpriced" ]]; then
    echo "  ⚠ 가격표에 없는 모델이 앱 기록에 있습니다: ${unpriced}— 공식 가격을 ModelPricing.table 에 넣으세요."; warn=1
  fi
  # 직전 릴리스 이후 기능이 바뀌었는데 README(세 언어)가 그대로면 기능 목록이 낡았을 수 있다.
  local last_tag feats readmes
  last_tag=$(last_release_tag)
  if [[ -n "$last_tag" ]]; then
    feats=$(git log "$last_tag"..HEAD --format='%s' -- Sources/ | grep -iE '^(feat|feature)[(:]' || true)
    readmes=$(git diff --name-only "$last_tag"..HEAD -- README.md README.ko.md README.ja.md | wc -l | tr -d ' ')
    if [[ -n "$feats" && "$readmes" -eq 0 ]]; then
      echo "  ⚠ $last_tag 이후 새 기능이 있는데 README(en/ko/ja)가 그대로입니다:"
      echo "$feats" | sed 's/^/       /'
      warn=1
    elif [[ "$readmes" -ne 0 && "$readmes" -ne 3 ]]; then
      echo "  ⚠ $last_tag 이후 README 가 ${readmes}개 언어만 바뀌었습니다 — en/ko/ja 를 함께 고치세요."; warn=1
    fi
  else
    echo "  (DigiTokenBar 의 이전 릴리스 태그 없음 — 첫 릴리스)"
  fi
  cat <<'CHECK'
  ─ 수동 체크리스트 (내용 변경 시 갱신) ─────────────────────────────
   [ ] README.md / .ko / .ja : 기능 목록·설치·요구사항·데이터 출처 — 세 언어 동시
   [ ] 릴리스 노트(PTB_NOTES_FILE): New / Fixed / Other / Contributors, Install / Upgrade
  ─────────────────────────────────────────────────────────────────
CHECK
  return $warn
}

if [[ "${1:-}" == "--check-only" ]]; then
  doc_check || true
  exit 0
fi

VERSION="${1:?사용: release.sh <version>  (예: 0.1.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ 버전 형식 오류: $VERSION"; exit 1; }
PREV=$(grep -oE 'VERSION="[0-9.]+"' scripts/build-app.sh | grep -oE '[0-9.]+')
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] || { echo "✗ main 브랜치에서 실행하세요 (현재: $BRANCH) — 커밋/push 대상 일치 보장"; exit 1; }
echo "=== $APP_NAME 릴리스 $PREV → $VERSION ==="

# Fail before tests, version changes, local installation, or publication.
NOTES_FILE="${PTB_NOTES_FILE:-}"
python3 scripts/release-metadata.py check-notes "$NOTES_FILE" "${PTB_CONTRIBUTORS_FILE:-}"
COMMIT_MESSAGE=$(python3 scripts/release-metadata.py commit-message "$VERSION" "${PTB_COAUTHORS_FILE:-}")

echo "▶ 1/8 릴리스 전 테스트 게이트"
./scripts/test-gate.sh >/dev/null || { echo "✗ test-gate 실패 — 중단"; exit 1; }
echo "  ✓ 통과"

echo "▶ 2/8 문서 검토 + 버전 확인"
# set -e 하에서 `doc_check; rc=$?` 는 실패 즉시 종료돼 rc 를 못 읽는다.
doc_rc=0; doc_check || doc_rc=$?
if [[ $doc_rc -ne 0 ]]; then
  if [[ ! -t 0 ]]; then
    echo "중단 — 문서 경고가 있습니다(터미널에서 직접 실행하면 확인 후 넘길 수 있습니다)."
    exit 1
  fi
  read -r -p "  문서 경고가 있습니다. 그래도 계속? [y/N] " a
  [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 문서 먼저 갱신하세요."; exit 1; }
fi
if [[ -n "$(git tag --list "v$VERSION")" ]] || gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  echo "✗ v$VERSION 태그나 릴리스가 이미 있습니다 — 다른 버전을 쓰세요."; exit 1
fi
LAST_TAG=$(last_release_tag)
if [[ -n "$LAST_TAG" ]]; then
  newest=$(printf '%s\n%s\n' "${LAST_TAG#v}" "$VERSION" | sort -V | tail -1)
  [[ "$newest" == "$VERSION" && "${LAST_TAG#v}" != "$VERSION" ]] \
    || { echo "✗ $VERSION 이 직전 릴리스 $LAST_TAG 보다 높지 않습니다."; exit 1; }
fi
echo "  ✓ 직전 릴리스: ${LAST_TAG:-없음(첫 릴리스)}"

echo "▶ 3/8 코드서명 신원 게이트 (ad-hoc 릴리스 차단으로 사용자 Keychain '항상 허용' 유지)"
# 릴리스가 ad-hoc(빌드마다 cdhash 변경) 또는 다른 인증서로 나가면, 기존 사용자의 Keychain "항상 허용"이
# 앱의 지정요구(DR: identifier + certificate leaf)와 안 맞아 매 업그레이드마다 깨진다 → Claude 한도 조회 시
# macOS 키체인 접근 다이얼로그가 재프롬프트된다. 안정적 자체서명 신원(고정 leaf)으로만 배포되게 강제한다.
# 자체서명이라 Gatekeeper(공증)는 통과하지 못한다 — 사용자는 처음 열 때 "확인되지 않은 개발자" 단계를 거친다.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-DigiTokenBar Local}"
# "DigiTokenBar Local" leaf SHA-1 — 설치본 DR 의 certificate leaf pin. 인증서를 재생성/교체하면 갱신 필요.
EXPECTED_LEAF="3CF2ED646F5BF6983B73892DD83B0C5471B19A0E"
LEAF=$(security find-identity -v -p codesigning | awk -v id="\"$SIGN_IDENTITY\"" '$0 ~ id {print $2; exit}')
if [[ -z "$LEAF" ]]; then
  echo "✗ 유효 codesigning identity '$SIGN_IDENTITY' 없음(미설치·만료 포함)."
  echo "  이대로면 build-app.sh 가 ad-hoc 서명 → 이 릴리스로 올린 사용자 전원이 Keychain 을 재승인해야 한다."
  echo "  복구: ./scripts/create-signing-cert.sh 실행 → 새 leaf 로 이 스크립트의 EXPECTED_LEAF 갱신 → 재실행."
  exit 1
fi
if [[ "$LEAF" != "$EXPECTED_LEAF" ]]; then
  echo "✗ 서명 인증서 leaf 불일치: 현재 $LEAF ≠ 고정 $EXPECTED_LEAF"
  echo "  인증서를 재생성/교체했다면, 이 릴리스로 업그레이드하는 기존 사용자 전원이 Keychain 을 1회 재승인해야 한다."
  if [[ ! -t 0 ]]; then echo "  터미널에서 직접 실행해 확인하세요."; exit 1; fi
  read -r -p "  의도한 변경이면 EXPECTED_LEAF 를 갱신하고 계속하세요. 지금 계속? [y/N] " a
  [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 서명 신원을 확인하세요."; exit 1; }
fi
echo "  ✓ '$SIGN_IDENTITY' leaf=$LEAF — 안정적 서명으로 배포(사용자 재프롬프트 없음)"
export PTB_REQUIRE_STABLE_SIGN=1   # build-app.sh 방어선: ad-hoc 폴백으로 새면 즉시 실패

echo "▶ 4/8 VERSION 범프 $PREV → $VERSION (아직 미커밋)"
perl -pi -e "s/VERSION=\"[0-9.]+\"/VERSION=\"$VERSION\"/" scripts/build-app.sh

echo "▶ 5/8 빌드 + zip (push 전 검증 — 실패해도 범프 미커밋이라 origin/main 무손상)"
./scripts/build-app.sh >/dev/null
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
[[ "$BUILT" == "$VERSION" ]] || { echo "✗ 빌드 버전 불일치: $BUILT (수동 복구: git checkout scripts/build-app.sh)"; exit 1; }
# 원본 v2.5.4 는 arm64 단일 바이너리로 나가 Intel 에서 "bad CPU type" 으로 실행 불가였다(#358).
# Xcode 27 의 lipo 는 -verify_arch 에 아키텍처를 하나씩만 받는다.
for arch in arm64 x86_64; do
  lipo "$APP/Contents/MacOS/$APP_NAME" -verify_arch "$arch" \
    || { echo "✗ universal 바이너리 아님: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME") (arm64 + x86_64 필요)"; exit 1; }
done
codesign --verify --strict "$APP" || { echo "✗ 서명 검증 실패"; exit 1; }
# Capture first, then match: `codesign … | grep -q` under pipefail fails whenever grep -q quits at the first
# match and codesign gets SIGPIPE (141), so a correctly signed app was reported as unsigned (v0.1.0).
SIGNATURE=$(codesign -dv --verbose=2 "$APP" 2>&1)
[[ "$SIGNATURE" == *"Authority=$SIGN_IDENTITY"* ]] || { echo "✗ '$SIGN_IDENTITY' 로 서명되지 않았습니다"; exit 1; }
echo "  ✓ $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' ')) — v$BUILT, arm64 + x86_64, '$SIGN_IDENTITY' 서명"

echo "▶ 6/8 커밋 + push (빌드 성공 후)"
if git diff --quiet -- scripts/build-app.sh; then
  echo "  (build-app.sh 가 이미 $VERSION — 범프 커밋 없이 현재 HEAD 를 배포)"
else
  git add scripts/build-app.sh
  git commit -q -m "$COMMIT_MESSAGE"
fi
git push -q origin main

echo "▶ 7/8 GitHub Release v$VERSION"
gh release create "v$VERSION" "$ZIP" --repo "$REPO" \
  --title "$APP_NAME v$VERSION" --target "$(git rev-parse HEAD)" --notes-file "$NOTES_FILE"

echo "▶ 8/8 Homebrew cask $VERSION ($TAP_REPO)"
SHA256=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
CASK_SHA=$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha')
TMP_CASK=$(mktemp)
gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.content' | base64 -d \
  | perl -pe "s/^(\s*version )\"[0-9.]+\"/\$1\"$VERSION\"/; s/^(\s*sha256 )\"[0-9a-f]+\"/\$1\"$SHA256\"/" > "$TMP_CASK"
grep -q "version \"$VERSION\"" "$TMP_CASK" && grep -q "sha256 \"$SHA256\"" "$TMP_CASK" \
  || { echo "✗ cask 갱신 내용 확인 실패 — 릴리스는 게시됨. $TAP_REPO 의 $CASK_PATH 를 손으로 $VERSION / $SHA256 로 고치세요."; exit 1; }
gh api -X PUT "repos/$TAP_REPO/contents/$CASK_PATH" -f message="cask: digitokenbar $VERSION" \
  -f content="$(base64 -i "$TMP_CASK")" -f sha="$CASK_SHA" --jq '.commit.html_url'
rm -f "$TMP_CASK"

echo "✓ v$VERSION 배포 완료: https://github.com/$REPO/releases/tag/v$VERSION"
echo "  확인: brew upgrade --cask deadlylaid/tap/digitokenbar, 그리고 릴리스의 $APP_NAME.zip 을 받아 codesign -dv · lipo -archs · 실행 (RELEASE.md §배포 후 검증)"
