import XCTest
@testable import PokeTokenBar

/// The confirmation shown before an import or a restore replaces the Digimon.
final class ImportConfirmPolicyTests: XCTestCase {
    /// [딥리뷰 M-f] 파괴적 버튼이 기본이면 Return 한 키로 진행이 대체된다. `NSAlert` 구성은 XCTest 에서
    /// 도달 불가라 규칙만 순수 함수로 빼 고정한다.
    func testCancelIsTheDefaultButtonOnTheImportConfirmation() {
        XCTAssertEqual(ImportConfirmPolicy.keyEquivalent(forButtonAt: ImportConfirmPolicy.cancelButtonIndex), "\r")
        XCTAssertEqual(ImportConfirmPolicy.keyEquivalent(forButtonAt: ImportConfirmPolicy.replaceButtonIndex), "",
                       "대체(파괴적) 버튼이 기본이면 안 된다")
    }
}
