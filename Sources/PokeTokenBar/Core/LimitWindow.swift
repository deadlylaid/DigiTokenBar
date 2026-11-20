import Foundation

/// A usage limit window: the 5-hour session or the weekly one.
enum WindowClass: Sendable { case session, weekly }

/// 돌봄 실수·디지몬 기분 판정 입력 — 프로바이더 무관 한도 창 1개. (UsageStore.candyEligibleWindows 가 생성;
/// 이름은 업스트림 사탕 지급에서 왔다)
struct CandyWindow: Sendable {
    let key: String          // 안정 식별자(tier 추적) — resets_at 등 휘발 필드는 key 에 넣지 않는다
    let name: String         // 표시용 창 이름
    let kind: WindowClass    // 세션(5시간) / 주간 — 새 창(epoch) 판정 기준이 다르다
    let utilization: Double  // 0~100+
    /// 창 epoch (`resets_at` / reset unix). key 는 안정, epoch 가 바뀌면 새 창 → 재무장(#326).
    /// nil 이면 100% 미만 관측으로만 재무장한다(Codex — credits 로 100% 를 넘겨 쓴다).
    let epoch: String?

    init(key: String, name: String, kind: WindowClass, utilization: Double, epoch: String? = nil) {
        self.key = key
        self.name = name
        self.kind = kind
        self.utilization = utilization
        self.epoch = epoch
    }
}

/// When a limit window's epoch (`resets_at`) really moved on to a new window.
enum LimitEpoch {
    /// Parse an epoch string into a Date, supporting Unix timestamp (seconds or ms) or ISO8601 strings.
    static func date(_ string: String) -> Date? {
        if let ts = Double(string) {
            if ts > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: ts / 1000.0)
            } else if ts > 100_000_000 {
                return Date(timeIntervalSince1970: ts)
            }
        }
        return ISO8601Parser.date(from: string)
    }

    /// Determines if a new epoch represents an actual window advancement (reset) rather than
    /// volatile network jitter (e.g. Codex ±1s) or fractional-second differences (Claude microseconds).
    /// For session windows (≈5h), requires advancing forward by at least 30 minutes.
    /// For weekly windows (7d), requires advancing forward by at least 24 hours.
    /// Non-date strings (used in synthetic unit tests) fall back to string inequality.
    static func isNew(previous: String, current: String, kind: WindowClass) -> Bool {
        guard previous != current else { return false }
        guard let dPrev = date(previous), let dCurr = date(current) else {
            return true
        }
        let delta = dCurr.timeIntervalSince(dPrev)
        let minAdvance: TimeInterval = kind == .weekly ? 86400 : 1800
        return delta >= minAdvance
    }
}
