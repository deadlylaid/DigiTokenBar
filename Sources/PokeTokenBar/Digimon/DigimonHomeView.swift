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
    var jogressTitle: String { ko ? "합체 진화했어요" : "Jogress evolution" }
    func todayExp(_ exp: Int, cap: Int) -> String { ko ? "오늘 \(exp)/\(cap) EXP" : "Today \(exp)/\(cap) EXP" }
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
    var fastGrowthHint: String {
        ko ? "진화에 필요한 경험치가 1/10이 돼요. 바쁜 하루면 부화부터 졸업까지 볼 수 있어요"
           : "Each stage needs a tenth of the experience: a busy day covers a whole life"
    }
    var fastGrowthOn: String { ko ? "빠른 성장 켜짐 (×10)" : "Fast growth on (×10)" }
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
    func tendencyTitle(_ attribute: DigimonAttribute) -> String {
        let name = self.attribute(attribute) ?? "?"
        return ko ? "지금은 \(name) 쪽으로 자라고 있어요" : "Growing toward \(name)"
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
    func bugsCaught(_ n: Int) -> String { ko ? "잡은 버그 \(n)마리" : "\(n) bugs caught" }
    var evolutionByCare: String {
        ko ? "어떤 모습이 될지는 키우는 방식(시간대, 도구, 한도, 버그 사냥)으로 정해져요"
           : "What it becomes depends on how you raise it (hours, tools, limits, bug hunting)"
    }
    var eggReady: String { ko ? "알을 고르면 바로 부화해요" : "Pick an egg and it hatches right away" }
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

/// Name, growth and evolution choice under the scene. Replaces the Pokemon companion header.
@MainActor
struct DigimonStatusView: View {
    let digimon: DigimonStore
    let hub: DigimonSceneHub
    let language: AppLanguage
    @State private var picked: String?

    private var t: DigimonText { DigimonText(language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameRow
            progress
            if !digimon.tendencies.isEmpty { tendency }
            if !digimon.candidates.isEmpty { choice }
            if digimon.canChooseEggLine { eggChoice }
        }
    }

    /// Before hatching, pick the line (the Vital Bracelet card) to raise: one of the eggs drawn for
    /// it, or a line raised before from the menu under them.
    private var eggChoice: some View {
        let catalog = digimon.engine.catalog
        let offered = digimon.eggOfferLines
        let others = digimon.otherEggLines
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
                            Text(t.eggOf(t.lineName(line, catalog: catalog)))
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
            if digimon.state.lifetimeSignals.bugsDefeated > 0 {
                Label("\(digimon.state.lifetimeSignals.bugsDefeated)", systemImage: "ant.fill")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .help(t.bugsCaught(digimon.state.lifetimeSignals.bugsDefeated))
            }
            if !digimon.state.graduates.isEmpty {
                Text(t.graduates(digimon.state.graduates.count)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(digimon.canSpecialJogress ? t.jogressLabel : t.progressLabel(digimon.state.partner.level))
                Spacer()
                Text("\(digimon.state.partner.stageExp) / \(digimon.threshold) EXP").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: digimon.progress)
            if digimon.isChoosingEgg, digimon.progress >= 1 {
                Text(t.eggReady).font(.caption).foregroundStyle(Color.accentColor)
            }
            if !digimon.isEgg, digimon.state.partner.level != .ultimate {
                Text(t.evolutionByCare).font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text(t.todayExp(digimon.expToday, cap: digimon.engine.growth.dailyExpCap))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
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
                    Text(t.attribute(row.attribute) ?? "?")
                        .font(.caption.weight(row.leading ? .semibold : .regular))
                        .frame(width: 58, alignment: .leading)
                    ProgressView(value: min(1, row.pull / top))
                        .tint(Self.color(row.attribute))
                }
            }
            Text(t.tendencyReasons(digimon.state.partner.stageSignals))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
