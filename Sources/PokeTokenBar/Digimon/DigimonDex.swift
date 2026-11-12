import SwiftUI

/// What the dex shows for one line, worked out from the save (pure, testable).
struct DigimonDex {
    enum Secret: Equatable {
        /// A special evolution with a condition (shown as a hint until met).
        case hidden(EvolutionRules.HiddenCondition)
        /// Not reachable yet (added after the MVP).
        case locked
        /// Only a Jogress (a merge with another Digimon) leads here, and growth does not merge.
        case mergeOnly
        /// A named Jogress the app does: raise both partners (e.g. War Greymon and Metal Garurumon).
        case specialJogress(partners: [String])
    }

    struct Link: Equatable, Identifiable {
        var id: String { key }
        let key: String
        /// The user has seen this evolution happen.
        let discovered: Bool
    }

    struct Entry: Equatable, Identifiable {
        var id: String { species.key }
        let species: DigimonSpecies
        let seen: Bool
        let secret: Secret?
        let previous: [Link]
        let next: [Link]
    }

    struct Row: Equatable, Identifiable {
        var id: DigimonLevel { level }
        let level: DigimonLevel
        let entries: [Entry]
    }

    static func rows(for line: DigimonLine, state: DigimonState, catalog: DigimonCatalog,
                     rules: EvolutionRules) -> [Row] {
        let members = line.members.compactMap(catalog.species)
        // Jogress-only steps are not growth routes, so the dex does not hint at them; the special
        // Jogress the app does is shown as an evolution.
        let special = rules.specialJogress.filter { line.members.contains($0.from) && line.members.contains($0.to) }
            .map { DigimonEvolution(from: $0.from, to: $0.to, sources: [.vitalBracelet], canon: false) }
        let evolutions = members.flatMap { catalog.nextEvolutions(from: $0.key, in: line) }
            .filter { !rules.lockedEdges.contains("\($0.from)>\($0.to)") } + special
        let allSteps = members.flatMap { catalog.nextEvolutions(from: $0.key, in: line) }
        func entry(_ species: DigimonSpecies) -> Entry {
            let incoming = allSteps.filter { $0.to == species.key }
            let mergeOnly = species.key != line.firstBaby && !incoming.isEmpty
                && incoming.allSatisfy { rules.lockedEdges.contains("\($0.from)>\($0.to)") }
            let jogressFrom = rules.specialJogress.filter { $0.to == species.key }.map(\.from)
            let secret: Secret? = !jogressFrom.isEmpty ? .specialJogress(partners: Array(Set(jogressFrom)).sorted())
                : rules.locked.contains(species.key) ? .locked
                : mergeOnly ? .mergeOnly
                : rules.hidden[species.key].map { .hidden($0) }
            let link = { (from: String, to: String, other: String) in
                Link(key: other, discovered: state.discoveredEvolutions.contains("\(from)>\(to)"))
            }
            return Entry(
                species: species,
                seen: state.dex.contains(species.key),
                secret: secret,
                previous: evolutions.filter { $0.to == species.key }.map { link($0.from, $0.to, $0.from) },
                next: evolutions.filter { $0.from == species.key }.map { link($0.from, $0.to, $0.to) })
        }
        return DigimonLevel.allCases.compactMap { level in
            let entries = members.filter { $0.level == level }.map(entry)
            return entries.isEmpty ? nil : Row(level: level, entries: entries)
        }
    }

    /// Species raised so far out of every species in the catalog's lines (shared ones count once).
    static func progress(state: DigimonState, catalog: DigimonCatalog) -> (seen: Int, total: Int) {
        let all = Set(catalog.lines.values.flatMap(\.members))
        return (all.intersection(state.dex).count, all.count)
    }
}

extension DigimonText {
    var dexTab: String { ko ? "도감" : "Dex" }
    func dexProgress(_ seen: Int, _ total: Int, graduates: Int) -> String {
        ko ? "도감 \(seen)/\(total) · 졸업 \(graduates)" : "Dex \(seen)/\(total) · \(graduates) graduated"
    }
    var unknownName: String { "???" }
    var evolvesFrom: String { ko ? "진화 전" : "From" }
    var evolvesTo: String { ko ? "진화 후" : "Into" }
    var noLinks: String { ko ? "없음" : "None" }
    var graduatesTitle: String { ko ? "졸업 기록" : "Graduates" }
    func secretHint(_ secret: DigimonDex.Secret) -> String {
        switch secret {
        case .locked: return ko ? "아직 만날 수 없어요." : "Not reachable yet."
        case .mergeOnly: return ko ? "다른 디지몬과 합체(조그레스)해야 만날 수 있어요. 아직은 만날 수 없어요."
                                  : "Only a Jogress (a merge) leads here, so it cannot be met yet."
        case .specialJogress(let partners):
            return ko ? "\(partners.count)마리를 모두 키워 보면, 궁극체를 다 채운 순간 졸업 대신 합체 진화해요."
                      : "Raise all \(partners.count) of them and a full Ultimate merges into this instead of graduating."
        case .hidden(.bugsDefeated): return ko ? "버그를 많이 잡은 디지몬이 이 모습이 된다는 소문이 있어요." : "Rumor says bug hunters turn into this."
        case .hidden(.limitHits): return ko ? "한도를 자주 넘긴 디지몬이 이 모습이 된다는 소문이 있어요." : "Rumor says hitting your limits often leads here."
        }
    }
    func lineName(_ line: DigimonLine, catalog: DigimonCatalog) -> String {
        name(catalog.species(line.id))
    }
    var chooseEggTitle: String { ko ? "어떤 알을 키울까요?" : "Which egg will you raise?" }
    var chooseEggHint: String { ko ? "부화하기 전까지 바꿀 수 있어요." : "You can switch until it hatches." }
    func eggOf(_ name: String) -> String { ko ? "\(name) 알" : "\(name) egg" }
}

/// The Dex tab: one line at a time, by level. Raised Digimon in color, the rest as silhouettes.
@MainActor
struct DigimonDexView: View {
    let digimon: DigimonStore
    let hub: DigimonSceneHub
    let language: AppLanguage
    @State private var lineID: String?
    @State private var selected: String?

    private var t: DigimonText { DigimonText(language) }
    private var catalog: DigimonCatalog { digimon.engine.catalog }
    private var shownLine: DigimonLine? { catalog.lines[lineID ?? digimon.state.partner.lineID] ?? digimon.line }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let progress = DigimonDex.progress(state: digimon.state, catalog: catalog)
            HStack {
                Text(t.dexProgress(progress.seen, progress.total, graduates: digimon.state.graduates.count))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Picker("", selection: Binding(get: { shownLine?.id ?? "" }, set: { lineID = $0; selected = nil })) {
                    ForEach(digimon.lines, id: \.id) { Text(t.lineName($0, catalog: catalog)).tag($0.id) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let line = shownLine {
                        let rows = DigimonDex.rows(for: line, state: digimon.state, catalog: catalog, rules: digimon.engine.rules)
                        if let entry = rows.flatMap(\.entries).first(where: { $0.id == selected }) {
                            detail(entry)
                        }
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.level(row.level)).font(.caption).foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                                    ForEach(row.entries) { cell($0) }
                                }
                            }
                        }
                    }
                    if !digimon.state.graduates.isEmpty { graduates }
                }
                .reservesScrollerLane()
            }
        }
    }

    private func cell(_ entry: DigimonDex.Entry) -> some View {
        let isSelected = selected == entry.id
        let isPartner = digimon.state.partner.speciesKey == entry.id
        return Button {
            selected = isSelected ? nil : entry.id
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    PixelSprite(data: hub.icons[entry.id], silhouette: !entry.seen)
                        .frame(width: 44, height: 44)
                    if entry.secret != nil, !entry.seen {
                        Image(systemName: entry.secret == .locked || entry.secret == .mergeOnly ? "lock.fill" : "sparkles")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(entry.seen ? t.name(entry.species) : t.unknownName)
                    .font(.caption2.weight(isPartner ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                isSelected || isPartner ? Color.accentColor : Color.secondary.opacity(0.2),
                lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .task(id: entry.id) { _ = await hub.image(for: entry.id) }
    }

    private func detail(_ entry: DigimonDex.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PixelSprite(data: hub.icons[entry.id], silhouette: !entry.seen).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.seen ? t.name(entry.species) : t.unknownName).font(.headline)
                    Text([t.level(entry.species.level), entry.seen ? t.attribute(entry.species.attribute) : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let secret = entry.secret, !entry.seen {
                Text(t.secretHint(secret)).font(.caption).foregroundStyle(.secondary)
            }
            links(t.evolvesFrom, entry.previous)
            links(t.evolvesTo, entry.next)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Paths the user has seen are named; the others stay "???".
    private func links(_ title: String, _ links: [DigimonDex.Link]) -> some View {
        let names = links.map { $0.discovered ? t.name(catalog.species($0.key)) : t.unknownName }
        return (Text(title + ": ").foregroundStyle(.secondary) + Text(names.isEmpty ? t.noLinks : names.joined(separator: ", ")))
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var graduates: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.graduatesTitle).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(digimon.state.graduates.enumerated().reversed()), id: \.offset) { _, record in
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.path.map { t.name(catalog.species($0)) }.joined(separator: " → "))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(record.graduatedAt, style: .date).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
