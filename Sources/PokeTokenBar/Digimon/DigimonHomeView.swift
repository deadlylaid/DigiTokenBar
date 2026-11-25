import AppKit
import SwiftUI

/// Words for the Digimon screens. Korean and English for now; other app languages use English.
struct DigimonText {
    let ko: Bool
    init(_ language: AppLanguage) { ko = language == .ko }

    func level(_ level: DigimonLevel) -> String {
        switch level {
        case .digitama: return ko ? "디지타마" : "Digi-Egg"
        case .babyI: return ko ? "유년기 I" : "Baby I"
        case .babyII: return ko ? "유년기 II" : "Baby II"
        case .child: return ko ? "성장기" : "Child"
        case .adult: return ko ? "성숙기" : "Adult"
        case .perfect: return ko ? "완전체" : "Perfect"
        case .ultimate: return ko ? "궁극체" : "Ultimate"
        }
    }

    func attribute(_ attribute: DigimonAttribute) -> String? {
        switch attribute {
        case .vaccine: return ko ? "백신" : "Vaccine"
        case .data: return ko ? "데이터" : "Data"
        case .virus: return ko ? "바이러스" : "Virus"
        case .free: return ko ? "프리" : "Free"
        case .unknown: return nil
        }
    }

    func name(_ species: DigimonSpecies?) -> String {
        guard let species else { return ko ? "디지타마" : "Digi-Egg" }
        return ko ? species.koreanName : species.name
    }

    func progressLabel(_ level: DigimonLevel) -> String {
        switch level {
        case .digitama: return ko ? "부화까지" : "Until it hatches"
        case .ultimate: return ko ? "졸업까지" : "Until graduation"
        default: return ko ? "다음 진화까지" : "Until the next evolution"
        }
    }

    var jogressLabel: String { ko ? "합체 진화까지" : "Until it merges" }
    var jogressWaiting: String { ko ? "친구의 합체 코드를 기다리는 중" : "Waiting for a friend's Jogress code" }

    // Jogress with a friend's code
    var jogressWaitTitle: String { ko ? "친구와 합체할 수 있어요" : "Jogress with a friend" }
    func jogressTimeLeft(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds) / 60), h = total / 60, m = total % 60
        if ko { return h > 0 ? "\(h)시간 \(m)분 남음" : "\(m)분 남음" }
        return h > 0 ? "\(h) h \(m) min left" : "\(m) min left"
    }
    var jogressExplain: String {
        ko ? "합체하려면 위 짝 조건에 맞는 디지몬을 키우는 친구의 코드가 필요해요. 친구 앱 홈의 이름 옆에 단계와 속성이 나와요. 친구가 배틀 칸의 '내 코드 복사'로 보낸 코드를 복사한 뒤 '받은 코드로 합체'를 눌러 주세요. 안 맞는 코드는 써도 없어지지 않아요. 시간이 지나면 평소처럼 진화하고, 기다리는 동안 쌓인 경험치는 다음 단계로 넘어가요."
           : "A Jogress needs a code from a friend raising a Digimon that fits a partner above. Their home shows its level and attribute next to its name. Copy the code they made with 'Copy my code' under Battle, then press 'Jogress with a code'. A code that does not fit is not used up. When time runs out it evolves as usual; EXP earned while waiting carries over."
    }
    /// The partner a route needs: a named Digimon, or attributes and a level ("백신·프리 성숙기").
    func jogressPartner(_ jogress: DigimonJogress, catalog: DigimonCatalog) -> String {
        if let key = jogress.species { return name(catalog.species(key)) }
        let attributes = jogress.attributes.sorted { $0.rawValue < $1.rawValue }.compactMap(attribute)
        return attributes.joined(separator: ko ? "·" : "/") + " " + (jogress.level.map(level) ?? "")
    }
    var jogressCodeButton: String { ko ? "받은 코드로 합체" : "Jogress with a code" }
    func jogressPartnerRow(_ need: String, results: [String]) -> String {
        ko ? "짝: \(need)  →  \(results.joined(separator: ", "))" : "Partner: \(need)  →  \(results.joined(separator: ", "))"
    }
    func jogressExampleLine(_ names: [String]) -> String {
        ko ? "예: \(names.joined(separator: ", "))" : "e.g. \(names.joined(separator: ", "))"
    }
    /// The text "Copy my code" puts on the clipboard: who the code is ("그레이몬 · 성숙기 · 백신") before
    /// the code, so a friend can tell whether it fits a Jogress before trying. Reading a code skips the
    /// words around it (`BattleCode.decode`).
    func labeledCode(_ code: String, species: DigimonSpecies?) -> String {
        guard let species else { return code }
        let label = [name(species), level(species.level), attribute(species.attribute)].compactMap { $0 }
            .joined(separator: " · ")
        return "\(label) | \(code)"
    }
    /// What a Jogress partner must be, in words: "백신 또는 프리 속성의 성숙기 디지몬" / "a Vaccine or Free Adult".
    /// A named partner is its name.
    func jogressNeed(_ jogress: DigimonJogress, catalog: DigimonCatalog) -> String {
        if let key = jogress.species { return name(catalog.species(key)) }
        let order: [DigimonAttribute] = [.vaccine, .data, .virus, .free]
        let attributes = order.filter(jogress.attributes.contains).compactMap(attribute)
        let lv = jogress.level.map(level) ?? ""
        return ko ? "\(attributes.joined(separator: " 또는 ")) 속성의 \(lv) 디지몬"
                  : "a \(attributes.joined(separator: " or ")) \(lv)"
    }
    /// Three Digimon that fit a partner kind, so the user knows whose code to ask for: ones they have met
    /// first (raised or seen as a visitor, 가나다 order), then well-known ones from the first lines (Agumon,
    /// Gabumon, Piyomon, Tentomon, Palmon, V-mon, Guilmon). Empty for a named partner.
    func jogressExamples(_ jogress: DigimonJogress, catalog: DigimonCatalog, met: Set<String>, count: Int = 3) -> [String] {
        guard jogress.species == nil, let lv = jogress.level else { return [] }
        let fits = { (s: DigimonSpecies) in s.level == lv && jogress.attributes.contains(s.attribute) }
        let locale = Locale(identifier: ko ? "ko_KR" : "en_US")
        var keys = met.compactMap(catalog.species).filter(fits)
            .sorted { name($0).compare(name($1), options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending }
            .map(\.key)
        for line in ["agumon", "gabumon", "piyomon", "tentomon", "palmon", "vmon", "guilmon"] {
            for key in catalog.lines[line]?.members ?? [] where !keys.contains(key) {
                if let s = catalog.species(key), fits(s) { keys.append(key) }
            }
        }
        return keys.prefix(count).map { name(catalog.species($0)) }
    }
    func skipJogressButton(_ level: DigimonLevel) -> String {
        level == .ultimate ? (ko ? "합체 없이 졸업" : "Graduate without it") : (ko ? "합체 없이 진화" : "Evolve without it")
    }
    func jogressOfferBody(hours: Int) -> String {
        ko ? "\(hours)시간 안에 친구의 코드로 합체 진화할 수 있어요. 코드가 없으면 평소처럼 진화해요."
           : "For \(hours) hours a friend's code can merge it. Without one it evolves as usual."
    }
    func jogressDone(partner: String, into: String) -> String {
        ko ? "\(partner)와(과) 합체해서 \(into)(으)로 진화했어요!" : "Merged with \(partner) into \(into)!"
    }
    func jogressError(_ error: Error, catalog: DigimonCatalog) -> String {
        switch error {
        case JogressError.notOpen: return ko ? "지금은 합체할 수 없어요." : "No Jogress right now."
        case JogressError.partnerDoesNotFit(let key):
            let s = catalog.species(key)
            let what = [s.map { level($0.level) }, s.flatMap { attribute($0.attribute) }].compactMap { $0 }.joined(separator: " · ")
            return ko ? "짝이 맞지 않아요. 받은 코드의 디지몬: \(name(s)) (\(what))" : "Not a fitting partner. The code holds \(name(s)) (\(what))."
        case JogressError.alreadyUsed: return ko ? "이미 합체에 쓴 코드예요." : "That code was already used for a Jogress."
        case BattleCodeError.notACode:
            return ko ? "클립보드에 코드가 없어요. 친구가 보낸 코드(DTB1.로 시작)를 복사한 뒤 눌러 주세요."
                      : "No code on the clipboard. Copy the code your friend sent (it starts with DTB1.) first."
        case BattleCodeError.ownCode: return ko ? "내 코드예요. 친구가 보낸 코드를 복사해 주세요." : "That is your own code. Copy your friend's."
        default: return battleError(error)
        }
    }
    var jogressTitle: String { ko ? "합체 진화했어요" : "Jogress evolution" }
    /// Today's experience, without a cap: every token counts.
    func todayExp(_ exp: Int) -> String {
        let n = exp.formatted(.number.locale(Locale(identifier: ko ? "ko_KR" : "en_US")))
        return ko ? "오늘 얻은 경험치 \(n)" : "Today +\(n) EXP"
    }
    /// The stage as the card counts it: coding hours a day (Vital Values), trophies and battles.
    func cardProgress(hoursPerDay: Double, trophies: Int, battles: Int, winPercent: Int) -> String {
        let hours = String(format: "%.1f", hoursPerDay)
        return ko ? "카드 조건: 하루 평균 코딩 \(hours)시간 · 트로피 \(trophies)개 · 배틀 \(battles)번(승률 \(winPercent)%)"
                  : "Card: \(hours) h of coding a day · \(trophies) trophies · \(battles) battles (\(winPercent)% won)"
    }
    // Battles
    var battleTitle: String { ko ? "배틀" : "Battle" }
    func battleStats(_ battles: Int, _ winPercent: Int) -> String {
        ko ? "이번 단계 \(battles)번 · 승률 \(winPercent)%" : "This stage: \(battles) · \(winPercent)% won"
    }
    func practiceButton(_ left: Int, of total: Int) -> String { ko ? "연습 배틀 (\(left)/\(total))" : "Practice (\(left)/\(total))" }
    var copyCodeButton: String { ko ? "내 코드 복사" : "Copy my code" }
    var codeBattleButton: String { ko ? "받은 코드로 배틀" : "Battle a code" }
    var battleHelp: String {
        ko ? "연습 배틀은 하루 5번, 같은 단계의 야생 디지몬과 싸워요. 다른 사용자와는 서로 코드를 보내고, 받은 코드를 복사한 뒤 '받은 코드로 배틀'을 누르면 두 앱에서 같은 배틀이 펼쳐져요. 코드 배틀은 3번으로 쳐요. 배틀은 경험치를 주지 않고, 카드 조건(배틀 수·승률)만 채워요."
           : "Practice: 5 a day against wild Digimon of the same level. With another user, send each other your codes; copy theirs and press 'Battle a code' and both apps play the same battle. A code battle counts three. Battles give no EXP, only the card's battle and win-ratio requirements."
    }
    var codeCopied: String {
        ko ? "내 배틀 코드를 복사했어요. 상대에게 보내고, 상대 코드도 받아서 '받은 코드로 배틀'을 눌러 주세요."
           : "Your battle code is copied. Send it, then copy theirs and press 'Battle a code'."
    }
    func battleResult(_ outcome: DigimonStore.BattleOutcome, foeName: String) -> String {
        let score = "\(outcome.result.myHits) : \(outcome.result.foeHits)"
        if ko {
            let kind = outcome.withCode ? "코드 배틀, 3번으로 셈" : "연습"
            return (outcome.result.won ? "이겼어요! " : "졌어요… ") + "\(score) · 상대: \(foeName) (\(kind))"
        }
        let kind = outcome.withCode ? "code battle, counts 3" : "practice"
        return (outcome.result.won ? "Won! " : "Lost… ") + "\(score) · vs \(foeName) (\(kind))"
    }
    func battleError(_ error: Error) -> String {
        switch error as? BattleCodeError {
        case .notACode?: return ko ? "클립보드에 배틀 코드가 없어요. 상대가 보낸 코드(DTB1.로 시작)를 복사한 뒤 눌러 주세요." : "No battle code on the clipboard. Copy the code you got (it starts with DTB1.) first."
        case .damaged?: return ko ? "코드가 잘렸거나 바뀌었어요. 다시 복사해 주세요." : "The code was cut or changed. Copy it again."
        case .unsupported?: return ko ? "이 앱에서 읽을 수 없는 코드예요." : "This app cannot read that code."
        case .unknownDigimon?: return ko ? "모르는 디지몬의 코드예요." : "That code holds a Digimon this app does not know."
        case .expired?: return ko ? "7일이 지난 코드예요. 새 코드를 받아 주세요." : "That code is over 7 days old. Ask for a new one."
        case .ownCode?: return ko ? "내 코드예요. 상대가 보낸 코드를 복사해 주세요." : "That is your own code. Copy theirs."
        case .alreadyFought?: return ko ? "이미 싸운 코드예요. 상대 코드는 하루에 한 번 바뀌어요." : "Already fought with that code. Codes change once a day."
        case nil: return ko ? "배틀을 할 수 없어요." : "No battle right now."
        }
    }
    var lockedTendency: String {
        ko ? "자물쇠가 있는 쪽은 코딩 시간, 트로피, 배틀을 더 채우면 열려요"
           : "Locked sides open with more coding hours, trophies or battles"
    }
    var cardProgressHint: String {
        ko ? "코딩 시간, 트로피, 배틀이 많을수록 어려운 진화가 열려요. 트로피는 코딩한 날 +1, 한도를 안 넘긴 날 +1, 도구를 2개 이상 쓴 날 +1이에요. 승률을 요구하는 진화도 있어요."
           : "More coding hours, trophies and battles open harder evolutions. Trophies: +1 for a day of coding, +1 without a full limit, +1 with two or more tools. Some need a win ratio."
    }
    var chooseTitle: String { ko ? "어떤 모습으로 진화할까요?" : "Which way should it evolve?" }
    func chooseDeadline(hours: Int) -> String {
        ko ? "\(hours)시간 안에 고르지 않으면 가장 잘 맞는 쪽으로 진화해요."
           : "If you don't pick within \(hours)h, it takes the best match."
    }
    var chooseButton: String { ko ? "이 모습으로 진화" : "Evolve into this" }
    func graduates(_ n: Int) -> String { ko ? "졸업한 디지몬 \(n)마리" : "\(n) graduated" }
    var feedsHint: String {
        ko ? "AI 코딩 도구에 새로 쓴 토큰을 먹고 자라요. 눌러서 공격!"
           : "Grows on the tokens you use with AI coding tools. Click to attack!"
    }
    var credit: String { ko ? "도트: Wikimon" : "Sprites: Wikimon" }
    var basedOn: String { ko ? "원본: PokeTokenBar (MIT)" : "Based on PokeTokenBar (MIT)" }

    // Settings
    var digimonSectionTitle: String { ko ? "디지몬" : "Digimon" }
    var fastGrowthLabel: String { ko ? "빠른 성장 (테스트)" : "Fast growth (testing)" }
    var stayInPlaceLabel: String { ko ? "제자리에 있기" : "Stay in place" }
    var stayInPlaceHint: String {
        ko ? "걸어 다니지 않고 가운데에 있어요(홈 장면과 바탕화면 펫). 숨쉬기·기지개·점프, 버그 사냥과 배틀은 그대로예요."
           : "It stays in the middle instead of walking around (Home and the desktop pet). Breathing, stretching, hops, bug hunts and battles stay."
    }
    var fastGrowthHint: String {
        ko ? "진화에 필요한 경험치가 1/10이 돼요. 바쁜 하루면 부화부터 졸업까지 볼 수 있어요"
           : "Each stage needs a tenth of the experience: a busy day covers a whole life"
    }
    var fastGrowthOn: String { ko ? "빠른 성장 켜짐 (×10)" : "Fast growth on (×10)" }
    var growthSpeedLabel: String { ko ? "성장 속도" : "Growth speed" }
    var growthSpeedHint: String {
        ko ? "하루에 쓰는 토큰이 적으면 빠르게, 많으면 느리게 골라 보세요. 1배는 하루 2억 토큰이면 알에서 졸업까지 열흘쯤이에요."
           : "Pick faster if you use few tokens a day, slower if you use many. At 1×, 200 million tokens a day take about ten days from egg to graduation."
    }
    func growthSpeed(_ speed: Double) -> String {
        let n = speed == speed.rounded() ? String(Int(speed)) : String(speed)
        return ko ? "\(n)배" : "\(n)×"
    }
    var growthPercent: String { ko ? "디지몬 성장률" : "Digimon growth %" }
    var growthPercentHint: String {
        ko ? "부화, 다음 진화, 졸업까지의 진행률" : "Progress toward hatching, the next evolution or graduation"
    }
    var deskPetTitle: String { ko ? "바탕화면 펫" : "Desktop pet" }
    var deskPetShow: String { ko ? "바탕화면 펫 표시" : "Show desktop pet" }
    var deskPetHint: String {
        ko ? "디지몬이 화면 위를 걸어 다녀요. 끌어서 옮기고, 누르면 공격해요."
           : "Your Digimon walks on the screen. Drag to move it, click to attack."
    }
    var agentActivityHint: String {
        ko ? "코딩 에이전트가 digitokenbar:// 링크를 보내면 디지몬이 반응해요"
           : "Coding agents can ping it with digitokenbar:// links"
    }
    // Backup & transfer
    var exportLabel: String { ko ? "디지몬 내보내기" : "Export Digimon" }
    var exportHint: String { ko ? "지금 디지몬, 도감, 졸업 기록을 파일 하나로 저장해요" : "Saves your Digimon, dex and graduates as one file" }
    var importLabel: String { ko ? "디지몬 불러오기" : "Import Digimon" }
    var importHint: String {
        ko ? "다른 Mac에서 내보낸 파일로 이어서 키워요. 지금 디지몬은 먼저 백업해요"
           : "Continue from a file exported on another Mac. The current one is backed up first"
    }
    var backupHint: String { ko ? "12시간마다 자동으로 백업해요 (최근 10개)" : "Backed up automatically every 12 hours (last 10 kept)" }
    var backupNowButton: String { ko ? "지금 백업" : "Back up now" }
    var backupDone: String { ko ? "백업했어요." : "Backed up." }
    var backupsTitle: String { ko ? "백업 목록" : "Backups" }
    var noBackups: String { ko ? "아직 백업이 없어요" : "No backups yet" }
    var restoreButton: String { ko ? "되돌리기" : "Restore" }
    var replaceButton: String { ko ? "바꾸기" : "Replace" }
    var importConfirmTitle: String { ko ? "이 파일의 디지몬으로 바꿀까요?" : "Replace your Digimon with this file?" }
    var restoreConfirmTitle: String { ko ? "이 백업으로 되돌릴까요?" : "Restore this backup?" }
    var importDone: String { ko ? "불러왔어요." : "Imported." }
    var restoreDone: String { ko ? "되돌렸어요." : "Restored." }
    func replaceBody(incoming: String, from: String, current: String) -> String {
        ko ? "불러올 디지몬: \(incoming)\n(\(from))\n\n지금 디지몬: \(current)\n지금 디지몬은 먼저 백업해요."
           : "Incoming: \(incoming)\n(\(from))\n\nCurrent: \(current)\nThe current one is backed up first."
    }
    /// "Agumon (Child) · dex 5 · 1 graduated"
    func summary(_ state: DigimonState, catalog: DigimonCatalog) -> String {
        let who = "\(name(state.partner.speciesKey.flatMap(catalog.species))) (\(level(state.partner.level)))"
        return ko ? "\(who) · 도감 \(state.dex.count) · 졸업 \(state.graduates.count)"
                  : "\(who) · dex \(state.dex.count) · \(state.graduates.count) graduated"
    }
    func saveError(_ error: Error, fallback: String) -> String {
        switch error as? DigimonSaveError {
        case .notADigimonSave: return ko ? "DigiTokenBar 저장 파일이 아니에요." : "This is not a DigiTokenBar save file."
        case .unknownLine(let key), .unknownSpecies(let key):
            return ko ? "이 버전이 모르는 디지몬이 들어 있어요 (\(key))." : "The file has a Digimon this version does not know (\(key))."
        case nil: return fallback
        }
    }

    // Coding agent bubbles on the desktop pet
    var agentWaiting: String { ko ? "확인이 필요해요" : "needs you" }
    var agentDone: String { ko ? "다 했어요!" : "all done!" }
    func agentMoreWaiting(_ n: Int) -> String { ko ? " 외 \(n)개" : " +\(n) more" }

    var notificationsLabel: String {
        ko ? "디지몬 알림 (부화·진화·선택·졸업)" : "Digimon events (hatch / evolve / choice / graduate)"
    }

    // Notifications
    var hatchedTitle: String { ko ? "디지타마가 부화했어요" : "Your Digi-Egg hatched" }
    var evolvedTitle: String { ko ? "진화했어요" : "Evolved" }
    var chooseNotifyTitle: String { ko ? "진화할 모습을 골라 주세요" : "Pick its next form" }
    func chooseNotifyBody(_ names: [String], hours: Int) -> String {
        ko ? "\(names.joined(separator: ", ")) 중에서 골라요. \(hours)시간이 지나면 자동으로 정해져요."
           : "Choose from \(names.joined(separator: ", ")). After \(hours)h it picks for you."
    }
    var graduatedTitle: String { ko ? "졸업했어요" : "Graduated" }
    func graduatedBody(_ name: String) -> String {
        ko ? "\(name)의 여정이 끝났어요. 새 알을 골라 주세요. 고를 때까지 부화하지 않아요."
           : "\(name)'s journey is complete. Pick a new egg: it waits for you before hatching."
    }
    func chooseEggWaiting(hours: Int) -> String {
        ko ? "고를 때까지 부화하지 않아요. 그동안 쓴 경험치는 모아 둬요. \(hours)시간이 지나면 자동으로 정해져요."
           : "It won't hatch until you pick, and keeps the experience meanwhile. After \(hours)h it picks for you."
    }
    /// The strongest lean of the stage. Not a promise: since step 14 the open routes are drawn by weight.
    func tendencyTitle(_ attribute: DigimonAttribute) -> String {
        let name = self.attribute(attribute) ?? "?"
        return ko ? "이번 단계는 \(name) 쪽으로 기울어 있어요" : "Leaning toward \(name) this stage"
    }
    /// What this stage has seen so far: the inputs of the tendency.
    func tendencyReasons(_ s: GrowthSignals) -> String {
        let night = Int((s.nightShare * 100).rounded())
        return ko ? "이번 단계: 새벽 \(night)% · 도구 \(s.providerCount)개 · 활동 \(s.activeDays.count)일 · 한도 초과 \(s.limitHits)회 · 버그 \(s.bugsDefeated)마리"
                  : "This stage: night \(night)% · \(s.providerCount) tools · \(s.activeDays.count) days · \(s.limitHits) limits hit · \(s.bugsDefeated) bugs"
    }
    var tendencyHint: String {
        ko ? "낮에 꾸준히 쓰면 백신, 여러 도구를 여러 날 쓰면 데이터, 새벽이 늘거나 한도를 넘기면 바이러스 쪽이에요."
           : "Steady daytime use leans Vaccine, many tools over many days Data, more late nights or full limits Virus."
    }
    func bugsCaught(_ n: Int) -> String { ko ? "이번 단계에 잡은 버그 \(n)마리" : "\(n) bugs caught this stage" }
    var evolutionByCare: String {
        ko ? "키우는 방식과 카드 조건, 약간의 운으로 모습이 정해져요"
           : "How you raise it, the card and a little luck decide its form"
    }
    var eggReady: String { ko ? "알을 고르면 바로 부화해요" : "Pick an egg and it hatches right away" }
    /// The home window's first line (`MenuBarHint`).
    var menuBarHint: String {
        ko ? "DigiTokenBar는 화면 오른쪽 위 메뉴 막대에 살아요. 아이콘이 안 보이면 메뉴 막대가 꽉 차서 노치 뒤에 숨은 거예요. 다른 메뉴 막대 앱을 줄이거나, 언제든 이 앱을 다시 열면(Spotlight, 응용 프로그램 폴더) 이 창이 떠요."
           : "DigiTokenBar lives in the menu bar, top right. If its icon is missing, a full menu bar has pushed it behind the notch: close a few other menu bar apps, or open this app again any time (Spotlight, Applications) to get this window."
    }
}

/// The pet scene at the top of the popover Home. It stays outside the scroll view: a web view
/// under the pointer would take the scroll gestures.
@MainActor
struct DigimonScenePanel: View {
    let hub: DigimonSceneHub
    let language: AppLanguage

    var body: some View {
        DigimonSceneView(hub: hub)
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .help(DigimonText(language).feedsHint)
    }
}

/// Name, growth and evolution choice under the scene.
@MainActor
struct DigimonStatusView: View {
    let digimon: DigimonStore
    let hub: DigimonSceneHub
    let language: AppLanguage
    @State private var picked: String?
    @State private var battleMessage: String?

    private var t: DigimonText { DigimonText(language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameRow
            progress
            if digimon.isJogressOpen { jogressWait }
            if digimon.isArmorOpen { armorWait }
            if !digimon.tendencies.isEmpty { tendency }
            if !digimon.candidates.isEmpty { choice }
            if digimon.canChooseEggLine { eggChoice }
            if digimon.canBattle { battle }
            DigimonTodayView(digimon: digimon, hub: hub, t: t)
        }
    }

    /// A full stage that can merge: the partners it takes, a friend's code, or evolving as usual.
    private var jogressWait: some View {
        let catalog = digimon.engine.catalog
        // One row per partner, with every result that partner leads to (unseen ones as ???).
        var rows: [(partner: String, results: [String])] = []
        let met = digimon.state.dex.union(digimon.state.sightings ?? [])
        for option in digimon.jogressOptions {
            let partner = t.jogressNeed(option, catalog: catalog)
            let result = digimon.state.dex.contains(option.to) ? t.name(catalog.species(option.to)) : t.unknownName
            if let i = rows.firstIndex(where: { $0.partner == partner }) {
                if !rows[i].results.contains(result) { rows[i].results.append(result) }
            } else {
                rows.append((partner, [result]))
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.jogressWaitTitle).font(.callout.weight(.semibold))
                Spacer()
                if let deadline = digimon.jogressDeadline {
                    Text(t.jogressTimeLeft(deadline.timeIntervalSinceNow)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            ForEach(rows, id: \.partner) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.jogressPartnerRow(row.partner, results: row.results)).font(.caption)
                    if let option = digimon.jogressOptions.first(where: { t.jogressNeed($0, catalog: catalog) == row.partner }) {
                        let examples = t.jogressExamples(option, catalog: catalog, met: met)
                        if !examples.isEmpty {
                            Text(t.jogressExampleLine(examples)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Button(t.jogressCodeButton) {
                    let text = NSPasteboard.general.string(forType: .string) ?? ""
                    do {
                        let partner = try digimon.jogress(withCode: text)
                        battleMessage = t.jogressDone(partner: t.name(catalog.species(partner)),
                                                      into: t.name(catalog.species(digimon.state.partner.speciesKey ?? "")))
                    } catch { battleMessage = t.jogressError(error, catalog: catalog) }
                }
                .buttonStyle(.borderedProminent)
                Button(t.skipJogressButton(digimon.state.partner.level)) { digimon.skipJogress() }
            }
            .controlSize(.small)
            Text(t.jogressExplain).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }

    /// A full stage that can armor-evolve with a Digimental the user owns: one button per route (an
    /// Armor not met yet stays a silhouette without its name), or growing as usual (it is kept).
    private var armorWait: some View {
        let catalog = digimon.engine.catalog
        let held = digimon.digimentalBag
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "diamond.fill").font(.caption).foregroundStyle(.orange)
                Text(t.armorWaitTitle).font(.callout.weight(.semibold))
                Spacer()
                if let deadline = digimon.armorDeadline {
                    Text(t.jogressTimeLeft(deadline.timeIntervalSinceNow)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            // One button per Armor and Digimental: Kongoumon opens with Miracles or with Fate, so a user
            // holding both picks which one to spend. A golden one is drawn in gold (step 16).
            ForEach(digimon.armorChoices) { option in
                let met = digimon.state.dex.contains(option.to)
                let golden = option.digimental.isGolden
                Button {
                    do { try digimon.useDigimental(to: option.to, with: option.digimental) } catch { battleMessage = t.armorError }
                } label: {
                    HStack(spacing: 6) {
                        PixelSprite(data: hub.icons[option.to], silhouette: !met).frame(width: 24, height: 24)
                        Text(met ? t.armorUseInto(option.digimental, name: t.name(catalog.species(option.to)))
                                 : t.armorUse(option.digimental))
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                        if golden { Image(systemName: "sparkles").font(.caption2).foregroundStyle(Color.digimentalGold) }
                        Text(t.ownedCount(held.owned(option.digimental))).font(.caption2)
                            .foregroundStyle(golden ? Color.digimentalGold : .orange).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .tint(golden ? Color.digimentalGold : nil)
                .controlSize(.small)
                .help(golden ? t.goldenTitle : "")
                .task(id: option.to) { _ = await hub.image(for: option.to) }
            }
            Button(digimon.isJogressOpen ? t.armorSkipKeepWaiting : t.armorSkip) { digimon.skipArmor() }
                .controlSize(.small)
            Text(t.armorExplain).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }

    /// Practice and code battles. The scene above plays each battle.
    private var battle: some View {
        let signals = digimon.state.partner.stageSignals
        let win = signals.battles > 0 ? signals.battleWins * 100 / signals.battles : 0
        let total = digimon.practiceLimit
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.battleTitle).font(.callout.weight(.semibold))
                Spacer()
                Text(t.battleStats(signals.battles, win)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 6) {
                Button(t.practiceButton(digimon.practiceLeft, of: total)) {
                    if let outcome = digimon.practiceBattle() { battleMessage = resultText(outcome) }
                }
                .disabled(digimon.practiceLeft == 0)
                Button(t.copyCodeButton) {
                    guard let code = digimon.myBattleCode() else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(t.labeledCode(code, species: digimon.species), forType: .string)
                    battleMessage = t.codeCopied
                }
                Button(t.codeBattleButton) {
                    let text = NSPasteboard.general.string(forType: .string) ?? ""
                    do { battleMessage = resultText(try digimon.battle(withCode: text)) }
                    catch { battleMessage = t.battleError(error) }
                }
            }
            .controlSize(.small)
            if let battleMessage {
                Text(battleMessage).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(t.battleHelp)
    }

    private func resultText(_ outcome: DigimonStore.BattleOutcome) -> String {
        let foe = digimon.engine.catalog.species(outcome.foe.species)
        let level = foe.map { t.level($0.level) } ?? ""
        return t.battleResult(outcome, foeName: "\(t.name(foe)) \(level)")
    }

    /// Before hatching, pick the line (the Vital Bracelet card) to raise: one of the eggs drawn for
    /// it, or a line raised before from the menu under them.
    private var eggChoice: some View {
        let catalog = digimon.engine.catalog
        let offered = digimon.eggOfferLines
        let others = t.sortedLines(digimon.otherEggLines, catalog: catalog)
        let current = digimon.state.partner.lineID
        return VStack(alignment: .leading, spacing: 6) {
            Text(t.chooseEggTitle).font(.callout.weight(.semibold))
            if !offered.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(3, offered.count)),
                          spacing: 6) {
                    ForEach(offered, id: \.id) { line in eggTile(line, catalog: catalog, picked: current == line.id) }
                }
            }
            if !others.isEmpty {
                Menu {
                    ForEach(others, id: \.id) { line in
                        Button {
                            digimon.chooseEggLine(line.id)
                        } label: {
                            Text(t.eggOf(t.lineName(line, catalog: catalog)) + (line.hasArmor ? " \(DigimonText.armorMark)" : ""))
                            if line.id == current { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    let pickedOther = others.first { $0.id == current }
                    Label(pickedOther.map { t.eggOf(t.lineName($0, catalog: catalog)) } ?? t.raisedLinesMenu,
                          systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(t.raisedLinesHelp)
            }
            Text(digimon.isChoosingEgg ? t.chooseEggWaiting(hours: digimon.eggChoiceHoursLeft ?? 0) : t.chooseEggHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(digimon.isChoosingEgg ? 10 : 0)
        .background(digimon.isChoosingEgg ? Color.accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func eggTile(_ line: DigimonLine, catalog: DigimonCatalog, picked: Bool) -> some View {
        let key = "egg_\(line.id)"
        return Button {
            digimon.chooseEggLine(line.id)
        } label: {
            VStack(spacing: 2) {
                PixelSprite(data: hub.icons[key]).frame(width: 28, height: 28)
                Text(t.eggOf(t.lineName(line, catalog: catalog))).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if line.hasArmor {
                    Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundStyle(.orange).padding(.trailing, 4)
                        .help(t.armorLineHelp)
                        .accessibilityLabel(t.armorLineHelp)
                }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                picked ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: picked ? 2 : 1))
        }
        .buttonStyle(.plain)
        .task(id: key) { _ = await hub.image(for: key) }
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            Text(t.name(digimon.species)).font(.title3.weight(.bold))
            if !digimon.isEgg { badge(t.level(digimon.state.partner.level)) }
            if let attribute = digimon.species.flatMap({ t.attribute($0.attribute) }) { badge(attribute) }
            Spacer()
            if digimon.bugsThisStage > 0 {
                Label("\(digimon.bugsThisStage)", systemImage: "ant.fill")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .help(t.bugsCaught(digimon.bugsThisStage))
            }
            if !digimon.state.graduates.isEmpty {
                Text(t.graduates(digimon.state.graduates.count)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(digimon.isJogressOpen ? t.jogressWaiting : digimon.isArmorOpen ? t.armorWaiting
                     : digimon.canSpecialJogress ? t.jogressLabel : t.progressLabel(digimon.state.partner.level))
                Spacer()
                // While waiting for a friend, EXP past the bar carries into the next stage.
                Text("\(min(digimon.state.partner.stageExp, digimon.threshold)) / \(digimon.threshold) EXP").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: digimon.progress)
            if digimon.isChoosingEgg, digimon.progress >= 1 {
                Text(t.eggReady).font(.caption).foregroundStyle(Color.accentColor)
            }
            if !digimon.isEgg, digimon.state.partner.level != .ultimate {
                Text(t.evolutionByCare).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)   // wraps instead of being cut off
            }
            HStack {
                Text(t.todayExp(digimon.expToday))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if digimon.isFastGrowth { Text(t.fastGrowthOn).foregroundStyle(.orange) }
            }
            .font(.caption2)
        }
    }

    /// Which way it is growing (attributes only, never the next form's name).
    private var tendency: some View {
        let rows = digimon.tendencies
        let top = max(rows.map(\.pull).max() ?? 1, 0.01)
        return VStack(alignment: .leading, spacing: 5) {
            if let lead = rows.first(where: \.leading) {
                Text(t.tendencyTitle(lead.attribute)).font(.callout.weight(.semibold))
            }
            ForEach(rows, id: \.attribute) { row in
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Text(t.attribute(row.attribute) ?? "?")
                            .font(.caption.weight(row.leading ? .semibold : .regular))
                        if !row.open { Image(systemName: "lock.fill").font(.system(size: 8)) }
                    }
                    .frame(width: 58, alignment: .leading)
                    ProgressView(value: min(1, row.pull / top))
                        .tint(Self.color(row.attribute))
                        .opacity(row.open ? 1 : 0.35)
                }
                .help(row.open ? "" : t.lockedTendency)
            }
            Text(t.tendencyReasons(digimon.state.partner.stageSignals))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let card = digimon.stagePerformance {
                Text(t.cardProgress(hoursPerDay: card.hoursPerDay, trophies: card.trophyCount,
                                    battles: card.battleCount, winPercent: card.winPercent))
                    .font(.caption2).foregroundStyle(.secondary)
                    .help(t.cardProgressHint)
                if rows.contains(where: { !$0.open }) {
                    Label(t.lockedTendency, systemImage: "lock.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .help(t.tendencyHint)
    }

    static func color(_ attribute: DigimonAttribute) -> Color {
        switch attribute {
        case .vaccine: return .blue
        case .data: return .green
        case .virus: return .purple
        case .free, .unknown: return .gray
        }
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t.chooseTitle).font(.callout.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(digimon.candidates, id: \.key) { species in
                    candidateCard(species)
                }
            }
            HStack {
                Text(t.chooseDeadline(hours: digimon.choiceHoursLeft ?? 0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button(t.chooseButton) {
                    if let picked { digimon.choose(picked) }
                    picked = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(picked.map { key in !digimon.candidates.contains { $0.key == key } } ?? true)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func candidateCard(_ species: DigimonSpecies) -> some View {
        let selected = picked == species.key
        return Button {
            picked = species.key
        } label: {
            VStack(spacing: 2) {
                PixelSprite(data: hub.icons[species.key]).frame(width: 48, height: 48)
                Text(t.name(species)).font(.caption.weight(.semibold)).lineLimit(1)
                Text([t.level(species.level), t.attribute(species.attribute)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .task(id: species.key) { _ = await hub.image(for: species.key) }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
    }
}

/// A pixel-art PNG (cropped to its pixels) standing on the bottom of the space it is given.
/// It grows only by whole steps (1x, 2x, ...) so pixels stay square, and shrinks only when it does
/// not fit at 1x. Empty while it is still downloading.
@MainActor
struct PixelSprite: View {
    let data: Data?
    /// Unmet Digimon in the dex: the shape only, in a muted color.
    var silhouette = false

    var body: some View {
        GeometryReader { geo in
            if let data, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 {
                let fit = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
                let scale = fit >= 1 ? fit.rounded(.down) : fit
                sprite(image)
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
        }
    }

    private func sprite(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .renderingMode(silhouette ? .template : .original)
            .interpolation(.none)
            .resizable()
            .foregroundStyle(Color.secondary.opacity(0.45))
    }
}
