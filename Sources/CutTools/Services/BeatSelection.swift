import Foundation

enum BeatFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case strong = "强拍"
    case transition = "能量转折"
    case highlights = "强拍与转折"
    case manual = "手动"
    var id: String { rawValue }
    func includes(_ marker: BeatMarker) -> Bool {
        switch self {
        case .all: return true
        case .strong: return marker.kind == "强拍候选"
        case .transition: return marker.kind == "能量转折候选"
        case .highlights: return marker.kind == "强拍候选" || marker.kind == "能量转折候选"
        case .manual: return marker.kind == "手动标记"
        }
    }
    func enabledOnly(_ markers: [BeatMarker]) -> [BeatMarker] {
        markers.map { var m = $0; m.enabled = includes(m); return m }
    }
}
