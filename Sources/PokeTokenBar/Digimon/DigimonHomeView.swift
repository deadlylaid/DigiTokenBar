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
        ko ? "\(name)의 여정이 끝났어요. 새 디지타마가 도착했어요." : "\(name)'s journey is complete. A new Digi-Egg arrived."
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
            if !digimon.candidates.isEmpty { choice }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            Text(t.name(digimon.species)).font(.title3.weight(.bold))
            badge(t.level(digimon.state.partner.level))
            if let attribute = digimon.species.flatMap({ t.attribute($0.attribute) }) { badge(attribute) }
            Spacer()
            if !digimon.state.graduates.isEmpty {
                Text(t.graduates(digimon.state.graduates.count)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t.progressLabel(digimon.state.partner.level))
                Spacer()
                Text("\(digimon.state.partner.stageExp) / \(digimon.threshold) EXP").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: digimon.progress)
            Text(t.todayExp(digimon.expToday, cap: digimon.engine.growth.dailyExpCap))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
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
                PixelSprite(data: hub.images[species.key]).frame(width: 48, height: 48)
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

/// A pixel-art PNG drawn without smoothing. Empty while it is still downloading.
@MainActor
struct PixelSprite: View {
    let data: Data?

    var body: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Color.clear
        }
    }
}
