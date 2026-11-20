import XCTest
@testable import PokeTokenBar

/// Placeholder-parity guard. `t(...)` enforces only the *number* of arguments —
/// nothing checks that a translation kept its `\(...)` placeholders, so a line
/// that dropped one still compiles. A defect like "the token count vanished, but
/// only in Portuguese" is caught by neither the build nor the existing tests, and
/// the gap widens with every language added.
/// Here each interpolated member is fed a sentinel that cannot occur in natural
/// copy, and every language's output must still contain it. Never a literal list
/// of languages: only `allCases` keeps coverage from silently stopping when a
/// new language lands.
/// (The French PR #185 proposes an equivalent guard. Whichever merges first, the
/// other copy can simply be dropped — the guard is not specific to a language.)
///
/// 치환자 보존 가드 — `t(...)` 가 강제하는 건 인자 *개수*뿐이라, 번역문이 `\(...)` 를 하나
/// 흘려도 컴파일은 그대로 통과한다. "포르투갈어 알림에서만 토큰 수가 사라진" 류의 결함은
/// 빌드도 기존 테스트도 못 잡고 그대로 출시된다 — 언어를 늘릴 때마다 커지는 공백이다.
/// 자연어에 절대 나타나지 않는 센티널을 넣고 모든 언어의 산출물에 살아있는지 확인한다.
/// 리터럴 언어 목록은 쓰지 않는다 — `allCases` 라야 언어가 늘어도 커버가 조용히 멈추지 않는다.
final class LocalizationInterpolationTests: XCTestCase {
    private static let a = "ZQXSENTINELA"
    private static let b = "ZQXSENTINELB"

    /// Failure text carries language, member and output, so a red run names the
    /// exact translation and the exact placeholder without any digging.
    /// 실패 메시지에 언어·멤버·산출물을 모두 담는다 — 어느 번역의 어느 치환자인지 바로 보이도록.
    private func expect(_ lang: AppLanguage, _ member: String, _ produced: String,
                        _ needles: String...,
                        file: StaticString = #filePath, line: UInt = #line) {
        for needle in needles {
            XCTAssertTrue(produced.contains(needle),
                          "\(lang.rawValue).\(member): '\(needle)' is missing → '\(produced)'",
                          file: file, line: line)
        }
    }

    func testInterpolationsSurviveInEverySupportedLanguage() {
        let a = Self.a
        let b = Self.b

        for lang in AppLanguage.allCases {
            let l = L(lang)

            // Limits & forecast / 한도 · 예측
            expect(lang, "plan", l.plan(a), a)
            expect(lang, "forecastReach", l.forecastReach(a), a)
            expect(lang, "claudeLimitEntry",
                   l.claudeLimitEntry(kind: "weekly_scoped", model: a), a)
            expect(lang, "limitsAccount", l.limitsAccount(a), a)
            expect(lang, "additionalClaudeAccountsFound", l.additionalClaudeAccountsFound(73), "73")
            expect(lang, "additionalClaudeAccountsDetected", l.additionalClaudeAccountsDetected(a), a)
            expect(lang, "additionalAccountExpiredHint", l.additionalAccountExpiredHint(a), a)
            expect(lang, "accountSessionKeyLabel", l.accountSessionKeyLabel(a), a)
            expect(lang, "unattributedClaudeUsage", l.unattributedClaudeUsage(a), a)
            expect(lang, "trackedAccountToolTip", l.trackedAccountToolTip(a), a)
            expect(lang, "codexWindow(h)", l.codexWindow(420), "7")     // 420 min → 7 h / 420분 → 7시간
            expect(lang, "codexWindow(m)", l.codexWindow(37), "37")
            expect(lang, "percentRemaining", l.percentRemaining(a), a)
            expect(lang, "paceHint", l.paceHint(a), a)
            expect(lang, "paceDelta(+)", l.paceDelta(4242) ?? "", "4242")
            expect(lang, "paceDelta(-)", l.paceDelta(-4242) ?? "", "4242")
            expect(lang, "limitRefreshHTTPError(401)", l.limitRefreshHTTPError(401), "401")
            expect(lang, "limitRefreshHTTPError(404)", l.limitRefreshHTTPError(404), "404")

            // Settings / 설정
            expect(lang, "intervalLabel", l.intervalLabel(1860), "31")  // 1860 s → 31 min / 1860초 → 31분
            expect(lang, "customScanRootsMatches", l.customScanRootsMatches(4242), "4242")

            // System notifications / 시스템 알림
            expect(lang, "notifBody", l.notifBody(a, b), a, b)

            // Updates / 업데이트
            expect(lang, "updateAvailable", l.updateAvailable(a, current: b), a, b)
            expect(lang, "updateFound", l.updateFound(a), a)
            expect(lang, "upToDate", l.upToDate(a), a)
            expect(lang, "skippedVersion", l.skippedVersion(a), a)
        }
    }

    /// Proves the guard above actually rejects a translation that dropped its
    /// placeholder — a test that only ever passes is indistinguishable from one
    /// that checks nothing. The defect is injected independently of Localization,
    /// so a green localized run cannot hide a broken predicate.
    /// 위 가드가 "치환자가 빠진 번역"에 실제로 실패하는지 — 통과만 보면 아무것도 안 지키는
    /// 테스트와 구별할 수 없다. Localization 과 독립적으로 결함을 주입해 판정부만 확인한다.
    func testGuardRejectsATranslationThatDroppedItsPlaceholder() {
        let intact = "Hoje: \(Self.a) tokens"
        let dropped = "Hoje: tokens"                     // \(tokens) dropped / \(tokens) 를 흘린 번역
        XCTAssertTrue(intact.contains(Self.a))
        XCTAssertFalse(dropped.contains(Self.a),
                       "letting a sentinel-less string pass would make the guard meaningless")
    }
}
