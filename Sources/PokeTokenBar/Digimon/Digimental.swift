import Foundation

/// The eleven Digimentals (Digimon Adventure 02, the D-3 toy; columns of Wikimon's Digimental Evolution
/// Chart). A Child holding the right one armor-evolves on the routes the Vital Bracelet cards give
/// (docs/digimon/step13-digimental-armor.md). The raw values are the ones the catalog and saves use.
enum Digimental: String, Codable, Sendable, CaseIterable, Hashable {
    case courage, friendship, love, knowledge, purity, reliability, hope, light, kindness, miracles, fate
}

extension DigimonText {
    /// "용기의 디지멘탈" / "Digimental of Courage".
    func digimental(_ d: Digimental) -> String {
        ko ? "\(digimentalWord(d))의 디지멘탈" : "Digimental of \(digimentalWord(d))"
    }

    /// The virtue alone ("용기" / "Courage"). Korean follows the Korean broadcast of Adventure 02.
    func digimentalWord(_ d: Digimental) -> String {
        switch d {
        case .courage: return ko ? "용기" : "Courage"
        case .friendship: return ko ? "우정" : "Friendship"
        case .love: return ko ? "사랑" : "Love"
        case .knowledge: return ko ? "지식" : "Knowledge"
        case .purity: return ko ? "순수" : "Purity"
        case .reliability: return ko ? "성실" : "Reliability"
        case .hope: return ko ? "희망" : "Hope"
        case .light: return ko ? "빛" : "Light"
        case .kindness: return ko ? "상냥함" : "Kindness"
        case .miracles: return ko ? "기적" : "Miracles"
        case .fate: return ko ? "운명" : "Fate"
        }
    }
}
