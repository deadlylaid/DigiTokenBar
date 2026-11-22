import SwiftUI

extension Color {
    /// The golden Digimentals (Miracles, Fate; step 16): their chips, armor buttons and count.
    static let digimentalGold = Color(red: 0.85, green: 0.64, blue: 0.08)
}

/// The Dex tab's Digimental area: what the user holds, fragments toward each Digimental, the two
/// fragments of the user's choice (a full stamp card, surprise points), and apart from them the two
/// golden Digimentals with their 30-point trade (step 16). Folded to one line by default.
@MainActor
struct DigimentalPanel: View {
    let digimon: DigimonStore
    let t: DigimonText
    @State private var expanded: Bool

    /// `expanded`: open from the start (for a capture of the whole area); the dex starts folded.
    init(digimon: DigimonStore, t: DigimonText, expanded: Bool = false) {
        self.digimon = digimon
        self.t = t
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        let bag = digimon.digimentalBag
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(width: 10)
                        Image(systemName: "diamond.fill").font(.caption).foregroundStyle(.orange)
                        Text(t.digimentalsTitle).font(.caption.weight(.semibold))
                        Text(t.digimentalsSummary(owned: bag.ownedTotal, fragments: bag.fragmentTotal))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        if bag.goldenTotal > 0 {
                            Image(systemName: "sparkles").font(.caption2).foregroundStyle(Color.digimentalGold)
                            Text(t.goldenShort(bag.goldenTotal)).font(.caption.weight(.semibold))
                                .foregroundStyle(Color.digimentalGold).monospacedDigit()
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.digimentalsHelp)
                .accessibilityLabel(t.digimentalsTitle)
                .accessibilityValue(t.digimentalsSummary(owned: bag.ownedTotal, fragments: bag.fragmentTotal))
                Spacer(minLength: 0)
            }
            // The picks get their own row: shown while open, or when one is ready to take.
            if expanded || digimon.stampRewardsPending > 0 || digimon.canExchangeSurprise {
                HStack(spacing: 12) {
                    if digimon.stampRewardsPending > 0 {
                        kindMenu(t.claimStampReward, systemImage: "gift.fill", help: t.stampRewardHelp, enabled: true) {
                            digimon.claimStampReward($0)
                        }
                    }
                    kindMenu(t.exchangeSurprise, systemImage: "exclamationmark.bubble.fill",
                             help: t.exchangeHelp(digimon.surprisePoints), enabled: digimon.canExchangeSurprise) {
                        digimon.exchangeSurprise(for: $0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
            }
            // The golden ones, apart and in gold: shown while open, or when 30 points can buy one.
            if expanded || digimon.canTradeForGolden {
                goldenRow(bag).padding(.leading, 14)
            }
            let now = digimon.digimentalsUsableNow.filter { bag.owned($0) > 0 }
            if expanded || !now.isEmpty {
                Text(t.partnerDigimentals(now: sorted(now), later: sorted(digimon.preferredDigimentals.subtracting(now)
                                                                              .filter { bag.owned($0) > 0 }),
                                          canUse: sorted(digimon.preferredDigimentals), open: digimon.isArmorOpen))
                    .font(.caption2).foregroundStyle(now.isEmpty ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
            }
            if expanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(bag.shownKinds(collectable: digimon.engine.fragmentKinds()), id: \.self) { chip($0, bag) }
                }
                Text(t.digimentalsHelp).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "용기 ●●○ ×1": the virtue, fragments toward the next one, and how many are held.
    private func chip(_ d: Digimental, _ bag: DigimentalBag) -> some View {
        let held = bag.owned(d), parts = bag.fragments(d)
        let usable = digimon.preferredDigimentals.contains(d)
        return HStack(spacing: 3) {
            Text(t.digimentalWord(d)).font(.caption2.weight(usable ? .bold : .regular)).lineLimit(1)
            HStack(spacing: 1) {
                ForEach(0..<DigimentalRules.fragmentsPerDigimental, id: \.self) { i in
                    Image(systemName: i < parts ? "circle.fill" : "circle").font(.system(size: 5))
                }
            }
            .foregroundStyle(parts > 0 ? Color.orange : Color.secondary.opacity(0.5))
            if held > 0 {
                Text(t.ownedCount(held)).font(.caption2.weight(.semibold)).foregroundStyle(.orange).monospacedDigit()
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(held > 0 ? Color.orange.opacity(0.6) : Color.secondary.opacity(0.2)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.digimental(d))
        .accessibilityValue("\(parts)/\(DigimentalRules.fragmentsPerDigimental) \(t.ownedCount(held))")
    }

    /// "✦ 황금 디지멘탈  기적 ×1  운명 ×0  [30점으로 받기]": one line, or the trade on a line of its own
    /// when it does not fit (English).
    private func goldenRow(_ bag: DigimentalBag) -> some View {
        let held = HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.caption).foregroundStyle(Color.digimentalGold)
            Text(t.goldenTitle).font(.caption.weight(.semibold)).foregroundStyle(Color.digimentalGold)
                .lineLimit(1).fixedSize()
            ForEach(Digimental.golden, id: \.self) { goldenChip($0, bag) }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                held
                if digimon.canTradeForGolden { goldenTradeMenu }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                held
                if digimon.canTradeForGolden { goldenTradeMenu }
            }
        }
        .help(t.goldenHelp)
    }

    /// Thirty surprise points for the golden Digimental the user picks (shown only when affordable).
    private var goldenTradeMenu: some View {
        Menu {
            ForEach(Digimental.golden, id: \.self) { d in
                Button(t.digimental(d)) { digimon.tradeForGolden(d) }
            }
        } label: {
            Label(t.goldenTrade, systemImage: "exclamationmark.bubble.fill").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(Color.digimentalGold)
        .help(t.goldenTradeHelp(digimon.surprisePoints))
    }

    /// "기적 ×1" in gold. Fragments only an old save holds still show as dots (they never fill).
    private func goldenChip(_ d: Digimental, _ bag: DigimentalBag) -> some View {
        let held = bag.owned(d), parts = bag.fragments(d)
        return HStack(spacing: 3) {
            Text(t.digimentalWord(d)).font(.caption2.weight(.bold)).lineLimit(1)
            if parts > 0 {
                HStack(spacing: 1) {
                    ForEach(0..<parts, id: \.self) { _ in Image(systemName: "circle.fill").font(.system(size: 5)) }
                }
            }
            Text(t.ownedCount(held)).font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(held > 0 ? Color.digimentalGold : Color.secondary)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.digimentalGold.opacity(held > 0 ? 0.16 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.digimentalGold.opacity(held > 0 ? 0.8 : 0.35)))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t.goldenTitle): \(t.digimental(d))")
        .accessibilityValue(t.ownedCount(held))
    }

    private func sorted(_ set: Set<Digimental>) -> [Digimental] { Digimental.allCases.filter(set.contains) }

    /// A small menu of the kinds to pick (the partner's usable ones first).
    private func kindMenu(_ title: String, systemImage: String, help: String, enabled: Bool,
                          action: @escaping (Digimental) -> Void) -> some View {
        Menu {
            ForEach(digimon.fragmentChoices, id: \.self) { d in
                Button(t.digimental(d)) { action(d) }
            }
        } label: {
            Label(title, systemImage: systemImage).font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: Armor evolution text

extension DigimonText {
    /// Marks a line where a Digimental opens a route (dex menu, egg choice).
    static let armorMark = "◆"
    var armorLineHelp: String { ko ? "디지멘탈로 아머 진화할 수 있는 줄기" : "A line that can armor-evolve with a Digimental" }
    var armorLineMenuHelp: String {
        ko ? "\(Self.armorMark) 표시는 디지멘탈로 아머 진화할 수 있는 줄기예요." : "\(Self.armorMark) marks a line that can armor-evolve with a Digimental."
    }

    var armorWaitTitle: String { ko ? "디지멘탈로 아머 진화할 수 있어요" : "Armor evolution with a Digimental" }
    var armorWaiting: String { ko ? "디지멘탈을 쓸지 기다리는 중" : "Waiting: use a Digimental?" }
    /// "용기의 디지멘탈로 아머 진화" (an Armor not met yet keeps its name hidden).
    func armorUse(_ d: Digimental) -> String { ko ? "\(digimental(d))로 아머 진화" : "Armor-evolve with the \(digimental(d))" }
    /// "용기의 디지멘탈로 화염드라몬" (an Armor already in the dex).
    func armorUseInto(_ d: Digimental, name: String) -> String {
        ko ? "\(digimental(d))로 \(name)" : "\(digimental(d)): \(name)"
    }
    var armorSkip: String { ko ? "그냥 진화" : "Evolve as usual" }
    /// While a friend's Jogress can still come, skipping the Digimental only stops waiting for it.
    var armorSkipKeepWaiting: String { ko ? "디지멘탈 쓰지 않기" : "Don't use a Digimental" }
    var armorExplain: String {
        ko ? "디지멘탈을 하나 쓰고 아머체로 진화해요. 아머체는 그다음 카드대로 자라요. '그냥 진화'를 누르거나 시간이 지나면 평소처럼 진화하고, 디지멘탈은 그대로 남아요."
           : "Uses up one Digimental and evolves into the Armor Digimon, which then grows on as its card says. 'Evolve as usual', or the time running out, evolves as usual and keeps the Digimental."
    }
    var armorError: String { ko ? "지금은 그 아머 진화를 할 수 없어요." : "That armor evolution is not open now." }
    func armorOfferBody(hours: Int) -> String {
        ko ? "\(hours)시간 안에 가진 디지멘탈로 아머 진화할 수 있어요. 쓰지 않으면 평소처럼 진화해요."
           : "For \(hours) hours a Digimental you hold can armor-evolve it. Without one it evolves as usual."
    }
    var armorEvolvedTitle: String { ko ? "아머 진화!" : "Armor evolution!" }
    func armorEvolvedBody(_ d: Digimental, from: String, to: String) -> String {
        ko ? "\(digimental(d)): \(from) → \(to)" : "\(digimental(d)): \(from) → \(to)"
    }

    /// The Digimental area's line about the current partner.
    /// `open`: the stage is full and waiting, so "now" means right now.
    func partnerDigimentals(now: [Digimental], later: [Digimental], canUse: [Digimental], open: Bool = false) -> String {
        let words = { (ds: [Digimental]) in ds.map(digimentalWord).joined(separator: ko ? "·" : ", ") }
        var parts: [String] = []
        if !now.isEmpty {
            parts.append(open ? (ko ? "지금 쓸 수 있어요: \(words(now))" : "Usable now: \(words(now))")
                              : (ko ? "이번 단계를 채우면 쓸 수 있어요: \(words(now))" : "Usable when this stage fills: \(words(now))"))
        }
        if !later.isEmpty { parts.append(ko ? "나중에 쓸 수 있어요: \(words(later))" : "Usable later: \(words(later))") }
        if !parts.isEmpty { return parts.joined(separator: "\n") }
        if canUse.isEmpty { return ko ? "지금 줄기에는 아머 진화가 없어요." : "No armor evolution on this line." }
        return ko ? "지금 디지몬이 쓸 디지멘탈: \(words(canUse))" : "Digimentals this Digimon can use: \(words(canUse))"
    }
}
