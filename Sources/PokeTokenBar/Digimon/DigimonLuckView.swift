import SwiftUI

extension DigimonText {
    var todayTitle: String { ko ? "오늘" : "Today" }

    func fortuneName(_ fortune: DigimonFortune) -> String {
        switch fortune {
        case .clear: return ko ? "맑음" : "Clear"
        case .bugSwarm: return ko ? "버그 소동" : "Bug swarm"
        case .fighting: return ko ? "투지" : "Fighting spirit"
        case .busy: return ko ? "손님 많은 날" : "Busy day"
        case .meteor: return ko ? "유성우" : "Meteor shower"
        }
    }

    func fortuneDetail(_ fortune: DigimonFortune) -> String {
        switch fortune {
        case .clear: return ko ? "평범한 하루예요." : "An ordinary day."
        case .bugSwarm: return ko ? "버그가 평소보다 자주 나와요." : "Bugs show up more often."
        case .fighting:
            return ko ? "연습 배틀을 \(LuckRules.extraPractice)번 더 할 수 있어요." : "\(LuckRules.extraPractice) more practice battles today."
        case .busy: return ko ? "손님이 두 번 와요." : "Two visitors come today."
        case .meteor: return ko ? "드문 손님이 오기 쉬워요." : "Rare visitors are more likely."
        }
    }

    func fortuneSymbol(_ fortune: DigimonFortune) -> String {
        switch fortune {
        case .clear: return "sun.max.fill"
        case .bugSwarm: return "ant.fill"
        case .fighting: return "flame.fill"
        case .busy: return "person.2.fill"
        case .meteor: return "sparkles"
        }
    }

    func tierName(_ tier: VisitorTier) -> String {
        switch tier {
        case .common: return ko ? "흔한 손님" : "Common"
        case .rare: return ko ? "드문 손님" : "Rare"
        case .veryRare: return ko ? "아주 드문 손님" : "Very rare"
        case .legendary: return ko ? "전설의 손님" : "Legendary"
        }
    }

    func visitorNotifyTitle(_ tier: VisitorTier) -> String {
        ko ? "\(tierName(tier))이 왔어요!" : "A \(tierName(tier).lowercased()) visitor came!"
    }

    /// What the pet says when a visitor arrives (the scene's callout).
    func visitorGreeting(_ name: String, firstSeen: Bool) -> String {
        if firstSeen { return ko ? "처음 보는 디지몬이다!" : "Never seen this one!" }
        return ko ? "\(name) 왔다!" : "\(name)!"
    }
    var firstSeenNotifyTitle: String { ko ? "처음 보는 디지몬이 왔어요!" : "A Digimon you've never seen came by!" }
    var firstSeenBadge: String { ko ? "처음 봐요" : "New" }
    func surpriseTitle(_ points: Int) -> String { ko ? "놀람 \(points)" : "Surprise \(points)" }
    var surpriseHelp: String {
        ko ? "손님이 오면 쌓여요. 내 디지몬보다 높은 단계이거나 2단계 이상 낮으면 +\(LuckRules.surpriseStage), 처음 보는 디지몬이면 +\(LuckRules.surpriseFirstSeen)."
           : "Visitors add to it: +\(LuckRules.surpriseStage) for one at a higher stage than yours or two or more lower, +\(LuckRules.surpriseFirstSeen) for one never seen."
    }
    var visitorCame: String { ko ? "다녀갔어요" : "came by" }
    /// Who is still coming stays a surprise; only how many.
    func visitorsToCome(_ n: Int, cameAlready: Bool) -> String {
        if ko {
            if cameAlready { return n > 1 ? "오늘 손님이 \(n)번 더 와요." : "오늘 손님이 한 번 더 와요." }
            return n > 1 ? "오늘 손님이 \(n)번 와요." : "오늘 손님이 올 거예요."
        }
        if cameAlready { return n > 1 ? "\(n) more visitors come today." : "One more visitor comes today." }
        return n > 1 ? "\(n) visitors come today." : "A visitor comes today."
    }
    var noVisitorLeft: String { ko ? "오늘 올 손님은 다 왔어요." : "Today's visitors have all come." }
    var stampsTitle: String { ko ? "출석 도장" : "Stamps" }
    func stampsHelp(cards: Int) -> String {
        let done = cards > 0 ? (ko ? " 완성 \(cards)번." : " Completed \(cards)×.") : ""
        return (ko ? "코딩한 날마다 하나씩 찍혀요. \(LuckRules.stampCard)개를 모으면 아주 드문 손님이 바로 와요."
                   : "One for each day you code. \(LuckRules.stampCard) bring a very rare visitor at once.") + done
    }
    var metAsVisitor: String { ko ? "손님으로 만났어요." : "Met as a visitor." }
    func sightings(_ n: Int) -> String { ko ? "손님 \(n)종" : "\(n) visitors" }
}

extension VisitorTier {
    /// Rarity colors (as loot is colored in Diablo): gray, blue, gold, purple.
    var color: Color {
        switch self {
        case .common: return .secondary
        case .rare: return .blue
        case .veryRare: return .orange
        case .legendary: return .purple
        }
    }
}

/// Home: the day's fortune, today's visitors and the stamp card.
@MainActor
struct DigimonTodayView: View {
    let digimon: DigimonStore
    let hub: DigimonSceneHub
    let t: DigimonText

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(t.todayTitle).font(.callout.weight(.semibold))
                if let fortune = digimon.todayLuck?.fortune {
                    Label(t.fortuneName(fortune), systemImage: t.fortuneSymbol(fortune))
                        .font(.caption.weight(.semibold))
                    Text(t.fortuneDetail(fortune)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ForEach(Array(digimon.visitorsToday.enumerated()), id: \.offset) { _, visit in visitorRow(visit) }
            if digimon.todayLuck != nil {
                Text(digimon.visitorsToCome > 0
                     ? t.visitorsToCome(digimon.visitorsToCome, cameAlready: !digimon.visitorsToday.isEmpty)
                     : t.noVisitorLeft)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            stamps
        }
    }

    private func visitorRow(_ visit: DigimonVisit) -> some View {
        let species = digimon.engine.catalog.species(visit.species)
        return HStack(spacing: 6) {
            PixelSprite(data: hub.icons[visit.species]).frame(width: 28, height: 28)
            Text(t.name(species)).font(.caption.weight(.semibold))
            Text(t.tierName(visit.tier)).font(.caption2.weight(.semibold)).foregroundStyle(visit.tier.color)
            if visit.firstSeen {
                Text(t.firstSeenBadge).font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
            }
            Text(t.visitorCame).font(.caption2).foregroundStyle(.secondary)
            if visit.points > 0 {
                Text("+\(visit.points)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                    .help(t.surpriseHelp)
            }
        }
        .task(id: visit.species) { _ = await hub.image(for: visit.species) }
    }

    private var stamps: some View {
        HStack(spacing: 4) {
            Text(t.stampsTitle).font(.caption).foregroundStyle(.secondary)
            ForEach(0..<LuckRules.stampCard, id: \.self) { i in
                Image(systemName: i < digimon.stamps ? "seal.fill" : "seal")
                    .font(.caption2)
                    .foregroundStyle(i < digimon.stamps ? Color.accentColor : Color.secondary.opacity(0.5))
                    .help(t.stampsHelp(cards: digimon.stampCardsCompleted))
            }
            Spacer()
            if digimon.surprisePoints > 0 {
                Label(t.surpriseTitle(digimon.surprisePoints), systemImage: "exclamationmark.bubble.fill")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .help(t.surpriseHelp)
            }
        }
    }
}
