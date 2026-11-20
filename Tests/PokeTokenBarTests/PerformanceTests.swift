import XCTest
@testable import PokeTokenBar

// 성능(measure) + 스케일/비퇴화 검증. baseline 은 머신 의존이라 느슨하게(게이트는 정확성에).

// MARK: 순수 계산 핫패스

final class PureComputePerformanceTests: XCTestCase {
    func testLargeDailyReportDecode() {
        let rows = (0..<1000).map {
            "{\"date\":\"2026-06-\(($0 % 28) + 1)\",\"inputTokens\":\($0),\"outputTokens\":1," +
            "\"cacheCreationTokens\":2,\"cacheReadTokens\":3,\"totalTokens\":\($0),\"totalCost\":0.1}"
        }.joined(separator: ",")
        let json = Data("{\"daily\":[\(rows)]}".utf8)
        measure {
            let report = try! JSONDecoder().decode(DailyReport.self, from: json)
            XCTAssertEqual(report.daily.count, 1000)
        }
    }
}

// MARK: 메뉴바 애니메이션 idle 배터리 규율

/// 메뉴바 애니메이션의 fps 하한(사용자 설정 `AnimationQuality`)과 타이머 코얼레싱 규율. 여기선 그
/// 순수 판정만 고정한다.
@MainActor
final class AnimationQualityTests: XCTestCase {
    /// [회귀] 코얼레싱 tolerance 는 **늦게만** 발화시키므로 곧 재생 지연의 상한이다. 0.5 였을 때
    /// 2.75s 루프가 최대 4.13s 로 늘어 팝오버(tolerance 0)와 나란히 보면 메뉴바만 느렸다.
    /// 코얼레싱을 없애지 않으면서(>0) 늘어짐은 눈에 안 띄는 범위(≤15%)로 묶는다.
    func testToleranceDoesNotVisiblyStretchPlayback() {
        XCTAssertGreaterThan(AppDelegate.menuFrameTolerance, 0, "코얼레싱이 사라지면 wakeup 회귀")
        let loop = 2.75                       // 41-a.gif 실측 루프 길이
        let worstCase = loop * (1 + AppDelegate.menuFrameTolerance)
        XCTAssertLessThanOrEqual(worstCase, loop * 1.15,
                                 "최악의 경우 재생이 15% 이상 늘어지면 팝오버와 속도가 어긋나 보인다")
    }

    /// [회귀] **어떤 프리셋도 캡을 해제하지 못한다.** 사용자에게 fps 선택권을 주면서 0(네이티브)이
    /// 새는 게 가장 위험한 회귀 — 프리셋을 추가해도 이 가드가 자동으로 걸린다(개별 상수 단정과 달리).
    func testNoAnimationQualityPresetDisablesTheCap() {
        XCTAssertFalse(UsageStore.AnimationQuality.allCases.isEmpty)
        for q in UsageStore.AnimationQuality.allCases {
            XCTAssertGreaterThan(q.frameFloor, 0, "\(q.rawValue): 캡이 해제되면 idle wakeup 회귀")
        }
    }

    /// 프리셋 순서 계약 — powerSaver 가 가장 느리고(하한 큼) smooth 가 가장 부드럽다. 라벨과 실제
    /// 동작이 어긋나면 사용자가 정반대를 고르게 된다.
    func testAnimationQualityPresetsAreOrdered() {
        let q = UsageStore.AnimationQuality.self
        XCTAssertGreaterThan(q.powerSaver.frameFloor, q.balanced.frameFloor)
        XCTAssertGreaterThan(q.balanced.frameFloor, q.smooth.frameFloor)
    }

    /// 저전력 모드의 유효 하한 — 파생값이라 "복귀"는 lowPower=false 계산 그 자체다.
    /// 저전력이면 어떤 프리셋도 powerSaver 보다 빠르게 돌 수 없고(캡), 아니면 선택값 그대로.
    /// 프리셋이 늘어도 자동으로 걸리도록 개별 상수 대신 전 케이스를 돈다.
    func testLowPowerCapsEffectiveFloorAtPowerSaverAndDerivationRestoresChoice() {
        let saver = UsageStore.AnimationQuality.powerSaver.frameFloor
        for q in UsageStore.AnimationQuality.allCases {
            XCTAssertGreaterThanOrEqual(q.effectiveFrameFloor(lowPower: true), saver,
                                        "\(q.rawValue): 저전력에서 powerSaver 보다 빠르면 절전 실패")
            XCTAssertGreaterThanOrEqual(q.effectiveFrameFloor(lowPower: true), q.frameFloor,
                                        "\(q.rawValue): 저전력이 애니메이션을 더 빠르게 만들 수는 없다")
            XCTAssertEqual(q.effectiveFrameFloor(lowPower: false), q.frameFloor,
                           "\(q.rawValue): 저전력이 아니면 사용자 선택 그대로(자동 복귀)")
        }
    }
}
