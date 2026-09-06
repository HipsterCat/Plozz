import Foundation

/// Continue Watching defaults to the complete provider feed. Recency determines
/// order, not membership: an older next episode still belongs until the server
/// or viewer removes it. Optional restrictions are explicit caller overrides,
/// never implicit Home defaults.
public struct ContinueWatchingPolicy: Sendable, Equatable, Codable {
    /// An explicit presentation limit; `.max` keeps every eligible title.
    /// Providers use bounded requests even when the total result is unlimited.
    public var rowLimit: Int

    /// An opt-in age restriction for unstarted suggestions. Home leaves this
    /// `nil`: time away from a series is not an instruction to hide its next episode.
    public var nextUpCutoff: TimeInterval?

    /// How old loaded Home content may be before returning to Home refreshes it.
    ///
    /// Home cannot see a title watched, finished or dismissed on another device,
    /// because nothing tells it to look. Without a bound it will keep showing the
    /// row it built at launch for as long as the app stays open.
    ///
    /// Short, because the refresh it gates is **silent**: the loaded rows stay on
    /// screen and swap in place. The instinct to make this long comes from when a
    /// reappearance triggered a *loud* reload that flashed the skeleton and threw
    /// focus back to the top — that was worth suppressing for a minute or more,
    /// and it is not what happens now. What is left to weigh is a fan-out across
    /// every signed-in account, so this only needs to be long enough that flicking
    /// between tabs does not re-run one repeatedly.
    ///
    /// It also has to be shorter than the thing it is racing: someone removing a
    /// title in the Plex app and coming back to see it gone. At ninety seconds
    /// that took several attempts and looked exactly like the bug it was meant to
    /// fix.
    public var refreshAfter: TimeInterval

    public init(
        rowLimit: Int = .max,
        nextUpCutoff: TimeInterval? = nil,
        refreshAfter: TimeInterval = 15
    ) {
        self.rowLimit = max(1, rowLimit)
        self.nextUpCutoff = nextUpCutoff
        self.refreshAfter = max(0, refreshAfter)
    }

    public static let `default` = ContinueWatchingPolicy()

    /// Everything kept, with no age bound or presentation limit.
    public static let unbounded = ContinueWatchingPolicy(rowLimit: .max, nextUpCutoff: nil)

    /// Whether a title passes an explicitly configured age restriction.
    ///
    /// **Fail-open by construction.** A title is dropped only when it is known to
    /// be a suggestion *and* known to be old. Anything in progress, and anything
    /// whose recency a backend did not report, is kept — a missing timestamp is an
    /// absence of evidence, and guessing from it would quietly delete a title the
    /// viewer is halfway through.
    public func keeps(_ item: MediaItem, now: Date = Date()) -> Bool {
        guard let nextUpCutoff else { return true }
        // Started, therefore a promise to come back. Age is irrelevant.
        if (item.resumePosition ?? 0) > 0 { return true }
        // A suggestion. Providers stamp these with their series' last-played date
        // precisely so the row can order them; the same stamp bounds them here.
        guard let lastPlayedAt = item.lastPlayedAt else { return true }
        return now.timeIntervalSince(lastPlayedAt) <= nextUpCutoff
    }

    /// Applies an opt-in restriction before merging accounts. With the default
    /// policy this preserves the entire feed, including old next-up episodes.
    public func curated(_ items: [MediaItem], now: Date = Date()) -> [MediaItem] {
        guard nextUpCutoff != nil else { return items }
        return items.filter { keeps($0, now: now) }
    }
}
