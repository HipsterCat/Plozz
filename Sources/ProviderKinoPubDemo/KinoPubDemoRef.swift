import Foundation

/// How a demo item id encodes what it is.
///
/// The catalogue only has titles, so seasons and episodes are synthesised — and
/// they have to be addressable by id alone, because that is all the app hands
/// back when it asks for one. Encoding the parent in the id means no lookup
/// table to keep in sync, and a restored navigation stack resolves without any
/// state having survived alongside it.
///
///     "52759"          → the title
///     "52759:s:2"      → its second season
///     "52759:e:2.7"    → episode 7 of that season
enum KinoPubDemoRef {
    case title(String)
    case season(String, Int)
    case episode(String, Int, Int)

    init(_ id: String) {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, let titleID = parts.first.map(String.init) else {
            self = .title(id)
            return
        }
        switch parts[1] {
        case "s":
            guard let number = Int(parts[2]) else { self = .title(id); return }
            self = .season(titleID, number)
        case "e":
            let pair = parts[2].split(separator: ".")
            guard pair.count == 2, let season = Int(pair[0]), let number = Int(pair[1]) else {
                self = .title(id)
                return
            }
            self = .episode(titleID, season, number)
        default:
            self = .title(id)
        }
    }

    var id: String {
        switch self {
        case .title(let titleID): titleID
        case .season(let titleID, let number): "\(titleID):s:\(number)"
        case .episode(let titleID, let season, let number): "\(titleID):e:\(season).\(number)"
        }
    }
}
