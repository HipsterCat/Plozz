import Foundation

/// Counts encoded local sync payloads, not CloudKit storage, assets or transport overhead.
/// Only aggregate metadata leaves the sync owner; identifiers and credential bytes do not.
public struct SyncDataInventory: Equatable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case profiles, profileAccess, servers, settings, watchlist, mediaMatches
        case liveTVSources, liveTVPreferences, libraryChannelSchedules, trackerSignIns, bookkeeping, other

        public var title: LocalizedStringResource {
            switch self {
            case .profiles: "Profiles"
            case .profileAccess: "Profile access"
            case .servers: "Servers"
            case .settings: "Settings"
            case .watchlist: "Watchlist"
            case .mediaMatches: "Media matches"
            case .liveTVSources: "Live TV sources"
            case .liveTVPreferences: "Live TV preferences"
            case .libraryChannelSchedules: "Plozz Channels schedules"
            case .trackerSignIns: "Tracker sign-ins"
            case .bookkeeping: "Sync bookkeeping"
            case .other: "Other sync data"
            }
        }
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public let category: Category
        public internal(set) var recordCount = 0
        public internal(set) var payloadBytes: Int64 = 0
        public internal(set) var pendingUploads = 0
        public internal(set) var pendingUploadBytes: Int64 = 0
        public internal(set) var pendingDeletions = 0
        public var id: Category { category }
    }

    private var totals: [Category: Row] = [:]
    public var rows: [Row] { Category.allCases.compactMap { totals[$0] } }
    public var recordCount: Int { rows.reduce(0) { $0 + $1.recordCount } }
    public var payloadBytes: Int64 { rows.reduce(0) { $0 + $1.payloadBytes } }
    public var pendingUploads: Int { rows.reduce(0) { $0 + $1.pendingUploads } }
    public var pendingUploadBytes: Int64 { rows.reduce(0) { $0 + $1.pendingUploadBytes } }
    public var pendingDeletions: Int { rows.reduce(0) { $0 + $1.pendingDeletions } }

    public init() {}

    public mutating func include(_ ledger: SyncLedger, category: (SyncRecordID) -> Category) {
        for (name, entry) in ledger.entries {
            let group = category(name)
            var row = totals[group] ?? Row(category: group)
            if entry.pendingDelete {
                row.pendingDeletions += 1
            } else {
                row.recordCount += 1
                row.payloadBytes += Int64(entry.localValue.count)
                if entry.dirty {
                    row.pendingUploads += 1
                    row.pendingUploadBytes += Int64(entry.localValue.count)
                }
            }
            totals[group] = row
        }
    }
}
