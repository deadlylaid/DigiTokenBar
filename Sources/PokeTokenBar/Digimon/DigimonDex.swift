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
        /// Only a Jogress leads here: a friend's code with a fitting partner (these routes).
        case friendJogress(routes: [DigimonJogress])
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
        /// Raised by the user.
        let seen: Bool
        /// Not raised, but met as a visitor: shown with its picture and name.
        var sighted = false
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
        // A merge-only step shows as an evolution when friends' codes can take it; the special Jogress
        // the app does is shown as one too.
        let special = rules.specialJogress.filter { line.members.contains($0.from) && line.members.contains($0.to) }
            .map { DigimonEvolution(from: $0.from, to: $0.to, sources: [.vitalBracelet], canon: false) }
        let friendSteps = rules.friendJogress ? Set(line.jogress.map(\.step)) : []
        let evolutions = members.flatMap { catalog.nextEvolutions(from: $0.key, in: line) }
            .filter { !rules.isLocked($0.from, $0.to, in: line) || friendSteps.contains("\($0.from)>\($0.to)") } + special
        let allSteps = members.flatMap { catalog.nextEvolutions(from: $0.key, in: line) }
        func entry(_ species: DigimonSpecies) -> Entry {
            let incoming = allSteps.filter { $0.to == species.key }
            let mergeOnly = species.key != line.firstBaby && !incoming.isEmpty
                && incoming.allSatisfy { rules.isLocked($0.from, $0.to, in: line) }
            let jogressFrom = rules.specialJogress.filter { $0.to == species.key }.map(\.from)
            let friendRoutes = rules.friendJogress ? line.jogress.filter { $0.to == species.key } : []
            let secret: Secret? = !jogressFrom.isEmpty ? .specialJogress(partners: Array(Set(jogressFrom)).sorted())
                : rules.locked.contains(species.key) ? .locked
                : mergeOnly ? (friendRoutes.isEmpty ? .mergeOnly : .friendJogress(routes: friendRoutes))
                : rules.hidden[species.key].map { .hidden($0) }
            let link = { (from: String, to: String, other: String) in
                Link(key: other, discovered: state.discoveredEvolutions.contains("\(from)>\(to)"))
            }
            let seen = state.dex.contains(species.key)
            return Entry(
                species: species,
                seen: seen,
                sighted: !seen && (state.sightings ?? []).contains(species.key),
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

// MARK: Search, filter, sort

extension DigimonDex {
    enum Status: CaseIterable, Hashable {
        case all, raised, metOnly, unknown
    }

    enum Sort: CaseIterable, Hashable {
        case level, name
    }

    /// What the search bar asks for. Any part of it set means "look through every line".
    struct Query: Equatable {
        var text = ""
        var status: Status = .all
        var level: DigimonLevel?
        var sort: Sort = .level

        var isActive: Bool { !Self.normalized(text).isEmpty || status != .all || level != nil || sort != .level }
        var isFiltered: Bool { status != .all || level != nil }

        /// Case, accents, width, spaces and punctuation do not matter: "war grey" finds "War Greymon".
        static func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .filter { $0.isLetter || $0.isNumber }
        }
    }

    /// One Digimon found, with the line its entry was read from (the one "show this line" opens).
    struct Hit: Equatable, Identifiable {
        var id: String { entry.id }
        let entry: Entry
        let lineID: String
    }

    /// Results under one level heading, or one list with no heading when sorted by name.
    struct Group: Equatable, Identifiable {
        var id: String { level?.rawValue ?? "all" }
        let level: DigimonLevel?
        let hits: [Hit]
    }

    /// Searches every line. `lines` is in the order to read them; a Digimon in several lines is shown
    /// once, from the first line where it is reachable without a secret (else the first line).
    ///
    /// A name only matches a Digimon whose name the dex shows (raised, or met as a visitor), so the
    /// search never gives away a silhouette.
    static func search(_ query: Query, lines: [DigimonLine], state: DigimonState, catalog: DigimonCatalog,
                       rules: EvolutionRules, text: DigimonText) -> [Group] {
        var best: [String: Hit] = [:]
        var order: [String] = []
        for line in lines {
            for entry in rows(for: line, state: state, catalog: catalog, rules: rules).flatMap(\.entries) {
                if let found = best[entry.id] {
                    if found.entry.secret != nil, entry.secret == nil { best[entry.id] = Hit(entry: entry, lineID: line.id) }
                } else {
                    best[entry.id] = Hit(entry: entry, lineID: line.id)
                    order.append(entry.id)
                }
            }
        }
        let needle = Query.normalized(query.text)
        let hits = order.compactMap { best[$0] }.filter { hit in
            let entry = hit.entry
            let named = entry.seen || entry.sighted
            switch query.status {
            case .all: break
            case .raised: if !entry.seen { return false }
            case .metOnly: if !entry.sighted { return false }
            case .unknown: if named { return false }
            }
            if let level = query.level, entry.species.level != level { return false }
            guard !needle.isEmpty else { return true }
            guard named else { return false }
            return [entry.species.koreanName, entry.species.name].contains { Query.normalized($0).contains(needle) }
        }
        // Named Digimon by their shown name, then the silhouettes (by level, then key).
        let locale = Locale(identifier: text.ko ? "ko_KR" : "en_US")
        let sorted = hits.sorted { a, b in
            let nameA = a.entry.seen || a.entry.sighted ? text.name(a.entry.species) : nil
            let nameB = b.entry.seen || b.entry.sighted ? text.name(b.entry.species) : nil
            switch (nameA, nameB) {
            case let (x?, y?):
                let order = x.compare(y, options: [.caseInsensitive], range: nil, locale: locale)
                return order == .orderedSame ? a.id < b.id : order == .orderedAscending
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return a.entry.species.level == b.entry.species.level ? a.id < b.id
                    : a.entry.species.level < b.entry.species.level
            }
        }
        switch query.sort {
        case .name:
            return sorted.isEmpty ? [] : [Group(level: nil, hits: sorted)]
        case .level:
            return DigimonLevel.allCases.compactMap { level in
                let inLevel = sorted.filter { $0.entry.species.level == level }
                return inLevel.isEmpty ? nil : Group(level: level, hits: inLevel)
            }
        }
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
    func secretHint(_ secret: DigimonDex.Secret, catalog: DigimonCatalog) -> String {
        switch secret {
        case .locked: return ko ? "아직 만날 수 없어요." : "Not reachable yet."
        case .mergeOnly: return ko ? "다른 디지몬과 합체(조그레스)해야 만날 수 있어요. 아직은 만날 수 없어요."
                                  : "Only a Jogress (a merge) leads here, so it cannot be met yet."
        case .friendJogress(let routes):
            // "아르고몬 + 백신·프리 성숙기", one per route.
            let ways = routes.map { "\(name(catalog.species($0.from))) + \(jogressPartner($0, catalog: catalog))" }.orderedUnique()
            return ko ? "친구와 합체해야 만날 수 있어요. 단계를 다 채운 뒤 맞는 짝을 키우는 친구의 코드로 합체해요: \(ways.joined(separator: ", "))"
                      : "Only a Jogress with a friend leads here. Once the stage is full, merge with a fitting friend's code: \(ways.joined(separator: ", "))"
        case .specialJogress(let partners):
            let names = partners.map { name(catalog.species($0)) }.joined(separator: ", ")
            return ko ? "\(names)를 모두 키워 본 적이 있으면, 궁극체를 다 채운 뒤 친구의 짝 디지몬 코드로 합체 진화해요."
                      : "Once you have raised \(names), a full Ultimate merges into this with a friend's code for its partner."
        case .hidden(.bugsDefeated): return ko ? "버그를 많이 잡은 디지몬이 이 모습이 된다는 소문이 있어요." : "Rumor says bug hunters turn into this."
        case .hidden(.limitHits): return ko ? "한도를 자주 넘긴 디지몬이 이 모습이 된다는 소문이 있어요." : "Rumor says hitting your limits often leads here."
        }
    }
    func lineName(_ line: DigimonLine, catalog: DigimonCatalog) -> String {
        name(catalog.species(line.id))
    }
    /// Lines in the order of their shown names (가나다 in Korean), the id breaking ties.
    func sortedLines(_ lines: [DigimonLine], catalog: DigimonCatalog) -> [DigimonLine] {
        let locale = Locale(identifier: ko ? "ko_KR" : "en_US")
        return lines.sorted { a, b in
            let order = lineName(a, catalog: catalog).compare(lineName(b, catalog: catalog), options: [.caseInsensitive],
                                                              range: nil, locale: locale)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }
    /// A line in the dex menu, with how often it graduated.
    func lineMenuName(_ line: DigimonLine, catalog: DigimonCatalog, graduated: Int) -> String {
        let name = lineName(line, catalog: catalog)
        guard graduated > 0 else { return name }
        return ko ? "\(name) · 졸업 \(graduated)번" : "\(name) · \(graduated) graduated"
    }
    var chooseEggTitle: String { ko ? "어떤 알을 키울까요?" : "Which egg will you raise?" }
    var chooseEggHint: String { ko ? "부화하기 전까지 바꿀 수 있어요." : "You can switch until it hatches." }
    var raisedLinesMenu: String { ko ? "키워 본 줄기에서 고르기" : "Pick a line you've raised" }
    var raisedLinesHelp: String {
        ko ? "졸업시켜 본 줄기는 언제든 다시 키울 수 있어요." : "Lines you've raised to graduation can always be raised again."
    }
    func eggOf(_ name: String) -> String { ko ? "\(name) 알" : "\(name) egg" }

    // Search bar
    var dexSearchPlaceholder: String { ko ? "이름으로 찾기" : "Search by name" }
    var dexFilterTitle: String { ko ? "거르기" : "Filter" }
    var dexStatusTitle: String { ko ? "보기" : "Show" }
    func dexStatus(_ status: DigimonDex.Status) -> String {
        switch status {
        case .all: return ko ? "모든 디지몬" : "All Digimon"
        case .raised: return ko ? "키워 본 디지몬" : "Raised"
        case .metOnly: return ko ? "손님으로만 만난 디지몬" : "Met only as visitors"
        case .unknown: return ko ? "아직 못 만난 디지몬" : "Not met yet"
        }
    }
    var dexLevelTitle: String { ko ? "단계" : "Level" }
    var dexAllLevels: String { ko ? "모든 단계" : "All levels" }
    var dexSortTitle: String { ko ? "정렬" : "Sort" }
    func dexSort(_ sort: DigimonDex.Sort) -> String {
        switch sort {
        case .level: return ko ? "단계순" : "By level"
        case .name: return ko ? "이름순" : "By name"
        }
    }
    func dexResults(_ count: Int) -> String { ko ? "모든 줄기에서 \(count)마리" : "\(count) across all lines" }
    var dexClearSearch: String { ko ? "지우기" : "Clear" }
    var dexNoResults: String { ko ? "조건에 맞는 디지몬이 없어요." : "No Digimon match." }
    var dexNoResultsByName: String {
        ko ? "찾는 디지몬이 없어요. 아직 못 만난 디지몬은 이름으로 찾을 수 없어요."
           : "No match. Digimon you haven't met can't be found by name."
    }
    func dexLineOf(_ name: String) -> String { ko ? "\(name) 줄기" : "\(name) line" }
    var dexShowLine: String { ko ? "이 줄기 보기" : "Show this line" }
}

/// The Dex tab: one line at a time, by level. Raised Digimon in color, the rest as silhouettes.
@MainActor
struct DigimonDexView: View {
    let digimon: DigimonStore
    let hub: DigimonSceneHub
    let language: AppLanguage
    @State private var lineID: String?
    @State private var selected: String?
    @State private var query = DigimonDex.Query()

    private var t: DigimonText { DigimonText(language) }
    private var catalog: DigimonCatalog { digimon.engine.catalog }
    private var shownLine: DigimonLine? { catalog.lines[lineID ?? digimon.state.partner.lineID] ?? digimon.line }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // One row when it fits; otherwise (longer English text) the line menu goes under the counts.
            ViewThatFits(in: .horizontal) {
                HStack {
                    counts
                    Spacer()
                    linePicker
                }
                VStack(alignment: .leading, spacing: 6) {
                    counts
                    linePicker
                }
            }
            DigimentalPanel(digimon: digimon, t: t)
            searchBar
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if query.isActive {
                        results
                    } else if let line = shownLine {
                        let rows = DigimonDex.rows(for: line, state: digimon.state, catalog: catalog, rules: digimon.engine.rules)
                        if let entry = rows.flatMap(\.entries).first(where: { $0.id == selected }) {
                            detail(entry)
                        }
                        ForEach(rows) { row in
                            grid(title: t.level(row.level), entries: row.entries)
                        }
                    }
                    if !query.isActive, !digimon.state.graduates.isEmpty { graduates }
                }
                .reservesScrollerLane()
            }
        }
    }

    private var counts: some View {
        let progress = DigimonDex.progress(state: digimon.state, catalog: catalog)
        return HStack {
            Text(t.dexProgress(progress.seen, progress.total, graduates: digimon.state.graduates.count))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            if digimon.sightingsCount > 0 {
                Label(t.sightings(digimon.sightingsCount), systemImage: "eye.fill")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// Picking a line goes back to browsing it.
    private var linePicker: some View {
        Picker("", selection: Binding(get: { shownLine?.id ?? "" },
                                      set: { lineID = $0; selected = nil; query = DigimonDex.Query() })) {
            let graduated = Dictionary(grouping: digimon.state.graduates, by: \.lineID).mapValues(\.count)
            ForEach(t.sortedLines(digimon.lines, catalog: catalog), id: \.id) { line in
                Text(t.lineMenuName(line, catalog: catalog, graduated: graduated[line.id] ?? 0)).tag(line.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(t.dexSearchPlaceholder, text: $query.text)
                    .textFieldStyle(.plain)
                if !query.text.isEmpty {
                    Button { query.text = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(t.dexClearSearch)
                }
            }
            .font(.callout)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
            Menu {
                Picker(t.dexStatusTitle, selection: $query.status) {
                    ForEach(DigimonDex.Status.allCases, id: \.self) { Text(t.dexStatus($0)).tag($0) }
                }
                .pickerStyle(.inline)
                Picker(t.dexLevelTitle, selection: $query.level) {
                    Text(t.dexAllLevels).tag(DigimonLevel?.none)
                    ForEach(DigimonLevel.allCases.filter { $0 != .digitama }, id: \.self) {
                        Text(t.level($0)).tag(DigimonLevel?.some($0))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: query.isFiltered ? "line.3.horizontal.decrease.circle.fill"
                                                   : "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(t.dexFilterTitle)
            .accessibilityLabel(t.dexFilterTitle)
            Menu {
                Picker(t.dexSortTitle, selection: $query.sort) {
                    ForEach(DigimonDex.Sort.allCases, id: \.self) { Text(t.dexSort($0)).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(t.dexSortTitle)
            .accessibilityLabel(t.dexSortTitle)
        }
    }

    @ViewBuilder
    private var results: some View {
        let lines = searchOrder
        let groups = DigimonDex.search(query, lines: lines, state: digimon.state, catalog: catalog,
                                       rules: digimon.engine.rules, text: t)
        let count = groups.reduce(0) { $0 + $1.hits.count }
        HStack {
            Text(t.dexResults(count)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button(t.dexClearSearch) {
                query = DigimonDex.Query()
                selected = nil
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        if count == 0 {
            Text(DigimonDex.Query.normalized(query.text).isEmpty ? t.dexNoResults : t.dexNoResultsByName)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let hit = groups.flatMap(\.hits).first(where: { $0.id == selected }) {
            detail(hit.entry, lineID: hit.lineID)
        }
        ForEach(groups) { group in
            grid(title: group.level.map(t.level), entries: group.hits.map(\.entry))
        }
    }

    /// The shown line first, then the rest in menu order: a Digimon shared by several lines is
    /// read from the one being browsed when it can be reached there.
    private var searchOrder: [DigimonLine] {
        let sorted = t.sortedLines(digimon.lines, catalog: catalog)
        guard let shown = shownLine else { return sorted }
        return [shown] + sorted.filter { $0.id != shown.id }
    }

    private func grid(title: String?, entries: [DigimonDex.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { Text(title).font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                ForEach(entries) { cell($0) }
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
                    PixelSprite(data: hub.icons[entry.id], silhouette: !entry.seen && !entry.sighted)
                        .frame(width: 44, height: 44)
                    if entry.sighted {
                        Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.secondary)
                    } else if entry.secret != nil, !entry.seen {
                        Image(systemName: entry.secret == .locked || entry.secret == .mergeOnly ? "lock.fill"
                              : { if case .friendJogress = entry.secret { return "person.2.fill" } else { return "sparkles" } }())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(entry.seen || entry.sighted ? t.name(entry.species) : t.unknownName)
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

    /// `lineID` is set for a search result: the detail then names its line and can open it.
    private func detail(_ entry: DigimonDex.Entry, lineID resultLine: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let resultLine, let line = catalog.lines[resultLine] {
                HStack {
                    Text(t.dexLineOf(t.lineName(line, catalog: catalog))).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(t.dexShowLine) {
                        lineID = resultLine
                        query = DigimonDex.Query()   // keeps `selected`: the line opens on this Digimon
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            HStack(spacing: 8) {
                PixelSprite(data: hub.icons[entry.id], silhouette: !entry.seen && !entry.sighted).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.seen || entry.sighted ? t.name(entry.species) : t.unknownName).font(.headline)
                    Text([t.level(entry.species.level), entry.seen ? t.attribute(entry.species.attribute) : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if entry.sighted {
                Text(t.metAsVisitor).font(.caption).foregroundStyle(.secondary)
            }
            if let secret = entry.secret, !entry.seen {
                Text(t.secretHint(secret, catalog: digimon.engine.catalog)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
