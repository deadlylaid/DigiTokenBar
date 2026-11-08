import XCTest
import Observation
@testable import PokeTokenBar

// MARK: 경제


// (부화 풀 하드코딩 제거 — 선정 로직 테스트는 CompanionIdentityTests 의 샘플러 테스트로 대체)

// MARK: 헬퍼

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class CountingRNG: RandomNumberGenerator {
    private var base: SeededRNG
    private(set) var callCount = 0

    init(seed: UInt64) { base = SeededRNG(seed: seed) }

    func next() -> UInt64 {
        callCount += 1
        return base.next()
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 1, _ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

@MainActor
private func waitUntilAsync(timeout: TimeInterval = 1, _ condition: @escaping () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await condition()
}

struct StubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    // 인덱스 = 자기 라인 base 단일 항목 → 선택 롤 1회 소비 후 항상 그 base (테스트 rng 재생 단순화)
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

private actor SuspendedLineProvider: PokeProviding {
    private let value: EvoLine
    private var continuation: CheckedContinuation<EvoLine, Never>?
    private var suspended = false

    init(value: EvoLine) { self.value = value }

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        await withCheckedContinuation { continuation in
            precondition(self.continuation == nil, "only one line request may be suspended")
            self.continuation = continuation
            suspended = true
        }
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        [BaseSpecies(id: value.baseID, captureRate: 255)]
    }

    func isSuspended() -> Bool { suspended }

    func resume() {
        let pending = continuation
        continuation = nil
        suspended = false
        pending?.resume(returning: value)
    }
}

private actor SuspendedFailingIndexProvider: PokeProviding {
    private var continuation: CheckedContinuation<[BaseSpecies], Error>?
    private var failNextRequest = false

    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }

    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if failNextRequest {
            failNextRequest = false
            throw URLError(.notConnectedToInternet)
        }
        return try await withCheckedThrowingContinuation { continuation in
            precondition(self.continuation == nil, "only one index request may be suspended")
            self.continuation = continuation
        }
    }

    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw URLError(.notConnectedToInternet) }
    func isSuspended() -> Bool { continuation != nil }

    func resumeFailure() {
        guard let pending = continuation else {
            failNextRequest = true
            return
        }
        continuation = nil
        pending.resume(throwing: URLError(.notConnectedToInternet))
    }
}

private actor SuspendedFailingLineProvider: PokeProviding {
    private var continuation: CheckedContinuation<EvoLine, Error>?
    private var failNextRequest = false

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if failNextRequest {
            failNextRequest = false
            throw URLError(.notConnectedToInternet)
        }
        return try await withCheckedThrowingContinuation { continuation in
            precondition(self.continuation == nil, "only one line request may be suspended")
            self.continuation = continuation
        }
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 25, captureRate: 255)] }
    func isSuspended() -> Bool { continuation != nil }

    func resumeFailure() {
        guard let pending = continuation else {
            failNextRequest = true
            return
        }
        continuation = nil
        pending.resume(throwing: URLError(.notConnectedToInternet))
    }
}

// 테스트 스텁 공통 — base 판정을 주입 인덱스에서 파생. REST 폴백 경로는 실클라이언트만 override.
extension PokeProviding {
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        try await baseSpeciesIndex().first { $0.id == id }
    }
}

private enum PokeStubError: Error { case boom }

/// GraphQL base 인덱스 장애 시뮬 — baseSpeciesIndex 는 throw(엔드포인트 다운), REST 폴백(baseSpecies)은 성공.
private struct FallbackOnlyProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { makeLine(base: baseSpeciesID, tree: node(baseSpeciesID)) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw PokeStubError.boom }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 100) }
}

/// line() 호출 횟수를 센다 — 이미 저장된 항목에 불필요한 조회가 붙는지 검증용.
private final class CountingLineProvider: PokeProviding, @unchecked Sendable {
    let value: EvoLine
    nonisolated(unsafe) private(set) var lineCalls = 0
    init(value: EvoLine) { self.value = value }
    func line(baseSpeciesID: Int) async throws -> EvoLine { lineCalls += 1; return value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

/// line() 자체가 실패(오프라인) — 도감 이름 조회 폴백 검증용.
private struct LineThrowsProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw PokeStubError.boom }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
}

/// 샘플러 테스트용 — 주입한 base 인덱스 + 요청 id 그대로의 무진화 라인 반환.
final class IndexProvider: PokeProviding, @unchecked Sendable {
    nonisolated(unsafe) var index: [BaseSpecies] = []
    nonisolated(unsafe) var failAll = false
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        makeLine(base: baseSpeciesID, tree: node(baseSpeciesID))
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if failAll { throw PokeStubError.boom }
        return index
    }
}

private func allIDs(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(allIDs) }
private func makeLine(base: Int, tree: EvoNode, rarity: Rarity = .common) -> EvoLine {
    var names: [Int: [String: String]] = [:]
    for id in allIDs(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: rarity, names: names)
}
private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
// 3단 선형: 1→2→3
private let linear3 = makeLine(base: 1, tree: node(1, [node(2, [node(3)])]))
// 분기: 10 → {11,12,13}
private let branch3 = makeLine(base: 10, tree: node(10, [node(11), node(12), node(13)]))
// Wurmple: 265 → {266 → 267, 268 → 269}
private let wurmpleLine = makeLine(base: 265, tree: node(265, [node(266, [node(267)]), node(268, [node(269)])]))
// Oddish: 43 → 44 → {45, 182}
private let delayedBranchLine = makeLine(base: 43, tree: node(43, [node(44, [node(45), node(182)])]))
// 무진화: 20
private let noEvo = makeLine(base: 20, tree: node(20))
private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: 스토어

@MainActor
final class CompanionStoreTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    // MARK: 상태 파일 decode 복원력 (회귀)


    /// [회귀] 전면 손상 상태 파일은 fresh 로 시작하되, 다음 save() 가 덮어써 영구 유실되기 전에
    /// 원본을 `.corrupt` 로 백업해 수동 복구 여지를 남긴다.
    func testCorruptStateFileBackedUpBeforeReset() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-corrupt-\(UUID().uuidString).json")
        let garbage = "this is not valid json {{{ 손상"
        try Data(garbage.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))

        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.usedSinceInstall, 0, "fresh state 로 시작")

        let backup = url.appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "손상 원본이 .corrupt 로 백업돼야 한다")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), garbage, "백업 내용 = 원본 그대로")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "원본은 이동돼 사라짐")
        try? FileManager.default.removeItem(at: backup)
    }


    // MARK: 도감 이름 (컬렉션 표시)





    // MARK: 도감 (종 단위 집계 — 로그의 개체 단위와 축이 다르다)






    // MARK: 대표 플로팅 펫 (육성 대상과 표시 대상 분리)









    // MARK: 도감 이름 백필 (격자는 저장분만 읽는다)




    // MARK: 도감 "키우는 중" 표식 (현재 형태 한 칸)



    // MARK: 놓아줌 (알 구매로 포기한 개체의 영구 기록)





    /// 이름 없는 구버전 졸업분 1건(체인 1→2→3)만 담긴 store — 백필/표식 테스트 공용.
    private func storeWithNamelessEntry() throws -> CompanionStore {
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode([bare]), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }


    func testInstallBaselineExcludesPreInstallUsage() {
        let s = store(linear3)
        // 데이터 도착 전 → baseline 미설정
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: false)
        XCTAssertFalse(s.state.installBaselineSet)
        // 첫 실데이터 → baseline = 그 시점 today(이전 사용량 미카운트)
        s.update(todayTokensByProvider: ["test": 48_000_000], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertTrue(s.state.installBaselineSet)
        XCTAssertEqual(s.state.usedSinceInstall, 0)
        // 이후 증가분만 누적
        s.update(todayTokensByProvider: ["test": 148_000_000], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 100_000_000)
    }

    /// [회귀] 로컬 사용량 재집계가 기존 값보다 낮아진 뒤에도, 새 기준점 이후의 증가분은 알에 반영한다.
    /// 예전에는 aggregate high-water mark 로만 유지해 감소 후 증가가 영구히 무시됐다.
    func testUsageIncreaseAfterValidDropContinuesEggProgress() {
        let s = store(linear3)
        base(s)
        use(s, 200)
        XCTAssertEqual(s.state.eggUsage, 200)

        // 유효한 낮은 스냅샷: 이 자체는 토큰 사용량으로 지급하지 않고 기준점만 재설정한다.
        use(s, 40)
        XCTAssertEqual(s.state.eggUsage, 200)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider?["test"], 40)

        // 새 기준점 이후의 증가분만 반영한다.
        use(s, 75)
        XCTAssertEqual(s.state.eggUsage, 235)
        XCTAssertEqual(s.state.usedSinceInstall, 235)
    }

    /// [회귀] 데이터 공백/조회 실패로 today=0 이 들어와도 당일 기준점을 0으로 낮추지 않는다.
    /// 다음 정상 조회 때 당일 전체를 중복 지급하면 안 된다.
    func testEmptyUsageSnapshotDoesNotRebaseDailyLedger() {
        let s = store(linear3)
        base(s)
        use(s, 200)

        use(s, 0, hasUsageData: false) // 빈 스냅샷/조회 공백
        XCTAssertEqual(s.state.eggUsage, 200)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider?["test"], 200)

        use(s, 250)
        XCTAssertEqual(s.state.eggUsage, 250)
        XCTAssertEqual(s.state.usedSinceInstall, 250)
    }

    /// [회귀] 프로바이더 하나가 일시적으로 snapshot을 내놓지 않아도 다른 프로바이더의
    /// 증가분만 적립하고, 사라졌던 프로바이더가 복구될 때 과거 사용량을 중복 지급하지 않는다.
    func testProviderLedgerDoesNotRecreditMissingProviderAfterPartialSnapshotLoss() {
        let s = store(linear3)
        useMap(s, ["claude_code": 0, "codex": 0])
        useMap(s, ["claude_code": 1_000, "codex": 500])
        XCTAssertEqual(s.state.usedSinceInstall, 1_500)

        // codex today == nil인 carrier snapshot은 map에서 빠진다. codex line은 그대로 보존한다.
        useMap(s, ["claude_code": 1_000], hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 1_500)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider,
                       ["claude_code": 1_000, "codex": 500])

        // 복구된 codex의 기존 500을 다시 지급하지 않고 이후 증가분만 지급한다.
        useMap(s, ["claude_code": 1_000, "codex": 500])
        XCTAssertEqual(s.state.usedSinceInstall, 1_500)
        useMap(s, ["claude_code": 1_000, "codex": 700])
        XCTAssertEqual(s.state.usedSinceInstall, 1_700)
    }

    /// [회귀] carrier만 남아 오늘 map이 비어도 프로바이더별 ledger를 0으로 낮추지 않는다.
    /// 정상 snapshot 복구 뒤에는 복구 시점 이후 증가분만 적립한다.
    func testCarrierWithoutTodayDataDoesNotRebaseProviderLedger() {
        let s = store(linear3)
        useMap(s, ["codex": 0])
        useMap(s, ["codex": 2_000])
        XCTAssertEqual(s.state.usedSinceInstall, 2_000)

        useMap(s, [:], hasUsageData: false)
        XCTAssertEqual(s.state.usedSinceInstall, 2_000)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["codex": 2_000])

        useMap(s, ["codex": 2_200])
        XCTAssertEqual(s.state.usedSinceInstall, 2_200)
    }

    /// [회귀] 날짜가 바뀌면 이전 날짜의 provider별 기준값과 비교하지 않고,
    /// 새 날짜에 이미 사용한 누적값 전체를 적립한 뒤 이후 증가분을 이어서 적립한다.
    func testDateRolloverCreditsCurrentDayUsage() {
        let s = store(linear3)
        useMap(s, ["codex": 0], date: "d1")
        useMap(s, ["codex": 200], date: "d1")
        XCTAssertEqual(s.state.usedSinceInstall, 200)

        useMap(s, ["codex": 100], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 300)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["codex": 100])

        useMap(s, ["codex": 150], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 350)
    }

    /// [회귀] 날짜 경계의 첫 refresh에서 provider 하나가 빠져도, 같은 날 복구된 현재 사용량을
    /// 누락하지 않는다. 이전 날짜의 ledger 값은 새 날짜와 비교할 수 없으므로 복구 provider의
    /// 새 날짜 기준은 0으로 열고, 그 날 처음 확인된 누적값을 적립한다.
    func testLateProviderRecoveryAfterDateRolloverCreditsCurrentDayUsage() {
        let s = store(linear3)
        useMap(s, ["claude_code": 0, "codex": 0], date: "d1")
        useMap(s, ["claude_code": 1_000, "codex": 500], date: "d1")
        XCTAssertEqual(s.state.usedSinceInstall, 1_500)

        // 날짜가 바뀐 첫 응답에는 codex가 빠졌다. Claude의 d2 사용량만 먼저 적립한다.
        useMap(s, ["claude_code": 100], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 1_600)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider,
                       ["claude_code": 100, "codex": 0])

        // 같은 날 codex가 복구되면 d2의 현재 누적값 전체가 적립되어야 한다.
        useMap(s, ["claude_code": 100, "codex": 700], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 2_300)

        // 이후에는 복구 시점 기준의 증가분만 적립한다.
        useMap(s, ["claude_code": 100, "codex": 900], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 2_500)
    }

    /// [회귀] stale snapshot처럼 오늘 provider map이 비어 있는 refresh는 날짜 경계를 소비하지
    /// 않는다. 다음 유효한 새 날짜 snapshot이 들어오면 그 시점의 오늘 사용량을 적립한다.
    func testStaleSnapshotDoesNotConsumeDateBoundary() {
        let s = store(linear3)
        useMap(s, ["codex": 0], date: "d1")
        useMap(s, ["codex": 200], date: "d1")

        useMap(s, [:], date: "d2", hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 200)
        XCTAssertEqual(s.state.lastDate, "d1")
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["codex": 200])

        useMap(s, ["codex": 100], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 300)
    }

    /// [마이그레이션] aggregate high-water mark만 가진 구버전 세이브는 값을 프로바이더별로
    /// 추정하지 않고 첫 유효 snapshot을 seed한다. 이후 증가분은 새 ledger로 정상 적립한다.
    func testLegacyAggregateLedgerSeedsProviderMapWithoutRetrospectiveCredit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let legacy = #"{"installBaselineSet":true,"usedSinceInstall":10000,"claimedTodayTokens":9000,"lastDate":"d1"}"#
        try Data(legacy.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow }, fileURL: url,
                               rng: SeededRNG(seed: 7))
        XCTAssertNil(s.state.claimedTodayTokensByProvider)

        s.update(todayTokensByProvider: ["codex": 500], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 10_000)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["codex": 500])

        s.update(todayTokensByProvider: ["codex": 700], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 10_200)
    }

    private func base(_ s: CompanionStore) {
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
    }
    private func use(_ s: CompanionStore, _ today: Int, hasUsageData: Bool = true) {
        s.update(todayTokensByProvider: ["test": today], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: hasUsageData)
    }
    private func useMap(_ s: CompanionStore, _ todayTokensByProvider: [String: Int], date: String = "d1",
                        hasUsageData: Bool = true) {
        s.update(todayTokensByProvider: todayTokensByProvider, todayDate: date, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: hasUsageData)
    }
































}

// MARK: 표시 로케일 (자동 생성 문장)

final class AppLanguageTests: XCTestCase {
    func testGermanLanguageMetadata() {
        XCTAssertEqual(AppLanguage.de.rawValue, "de")
        XCTAssertEqual(AppLanguage.de.apiCodes, ["de"])
        XCTAssertEqual(AppLanguage.de.label, "Deutsch")
    }

    func testGermanLanguagePersistsInCompanionState() throws {
        var state = CompanionState()
        state.language = .de

        let data = try JSONEncoder().encode(state)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""language":"de""#))
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: data).language, .de)
    }

    func testGermanPreferredLanguagesMapToGerman() {
        for identifier in ["de", "de-DE", "de-AT", "DE-de"] {
            XCTAssertEqual(AppLanguage.systemDefault(for: identifier), .de, identifier)
        }
        XCTAssertEqual(AppLanguage.systemDefault(for: "it-IT"), .en)
        XCTAssertEqual(AppLanguage.systemDefault(for: nil), .en)
    }

    func testRussianLanguageMetadata() {
        XCTAssertEqual(AppLanguage.ru.rawValue, "ru")
        XCTAssertEqual(AppLanguage.ru.apiCodes, ["ru"])
        XCTAssertEqual(AppLanguage.ru.label, "Русский")
    }

    func testRussianLanguagePersistsInCompanionState() throws {
        var state = CompanionState()
        state.language = .ru

        let data = try JSONEncoder().encode(state)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""language":"ru""#))
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: data).language, .ru)
    }

    func testRussianPreferredLanguagesMapToRussian() {
        for identifier in ["ru", "ru-RU", "ru-KZ", "RU-ru"] {
            XCTAssertEqual(AppLanguage.systemDefault(for: identifier), .ru, identifier)
        }
        XCTAssertEqual(AppLanguage.systemDefault(for: "uk-UA"), .en)
    }
}

/// 앱 언어와 시스템 로케일이 다를 때 `Text(_, style: .relative)` 같은 자동 문장이 시스템을 따라가면
/// 한 화면에 두 언어가 섞인다(한국어 Mac + 영어 앱 → "Catch log" 옆에 "3시간 46분").
/// 팝오버 루트가 `\.locale` 로 앱 언어를 내려주므로, 그 매핑이 실제로 해당 언어의 상대 시각을
/// 만들어내는지까지 고정한다 — 코드만 비교하면 잘못 매핑해도 통과한다.
final class DisplayLocaleTests: XCTestCase {
    func testDisplayLocaleMatchesLanguageCode() {
        XCTAssertEqual(AppLanguage.ko.displayLocale.identifier, "ko")
        XCTAssertEqual(AppLanguage.en.displayLocale.identifier, "en")
        XCTAssertEqual(AppLanguage.ja.displayLocale.identifier, "ja")
        XCTAssertEqual(AppLanguage.de.displayLocale.identifier, "de")
        XCTAssertEqual(AppLanguage.ru.displayLocale.identifier, "ru")
    }

    func testRelativeTimeFollowsAppLanguageNotSystem() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = now.addingTimeInterval(-3 * 3600)

        func relative(_ lang: AppLanguage) -> String {
            let f = RelativeDateTimeFormatter()
            f.locale = lang.displayLocale
            return f.localizedString(for: past, relativeTo: now)
        }

        XCTAssertTrue(relative(.en).contains("hour"), "영어: \(relative(.en))")
        XCTAssertTrue(relative(.ko).contains("시간"), "한국어: \(relative(.ko))")
        XCTAssertTrue(relative(.ja).contains("時間"), "일본어: \(relative(.ja))")
        XCTAssertTrue(relative(.de).lowercased().contains("stund"), "독일어: \(relative(.de))")
        XCTAssertTrue(relative(.ru).contains("час"), "러시아어: \(relative(.ru))")
        // 다섯 언어가 서로 달라야 한다 — 하나로 고정돼 있으면 매핑이 죽은 것이다.
        XCTAssertEqual(Set([relative(.en), relative(.ko), relative(.ja), relative(.de), relative(.ru)]).count, 5)
    }
}

// MARK: 포획 로그 정렬 / 요약


/// 테스트용 — 라인을 호출 전에 갈아끼울 수 있는 provider. 단일 스레드 테스트 한정.
private final class MutableProvider: PokeProviding, @unchecked Sendable {
    nonisolated(unsafe) var line: EvoLine = makeLine(base: 1, tree: node(1))
    func line(baseSpeciesID: Int) async throws -> EvoLine { line }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: line.baseID, captureRate: 255)] }
}

// MARK: 개체 아이덴티티 (shiny / nature) — v2.2.0


private struct FailingPokeProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        throw URLError(.notConnectedToInternet)
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        throw URLError(.notConnectedToInternet)
    }
}

// MARK: PokéAPI SSRF 가드 (evolution_chain URL 검증 — 응답 변조 시 임의 호스트 fetch 방지)

