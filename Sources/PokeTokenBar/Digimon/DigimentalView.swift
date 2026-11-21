import SwiftUI

/// The Dex tab's Digimental area: what the user holds, fragments toward each Digimental, and the two
/// fragments of the user's choice (a full stamp card, surprise points). Folded to one line by default.
@MainActor
struct DigimentalPanel: View {
    let digimon: DigimonStore
    let t: DigimonText
    @State private var expanded = false

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
            if expanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(Digimental.allCases, id: \.self) { chip($0, bag) }
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
