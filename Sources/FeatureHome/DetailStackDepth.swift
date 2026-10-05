import CoreNetworking
import CoreModels
import Foundation
import Observation
import SwiftUI

/// Tracks how many detail pages are currently on a navigation stack, so a page
/// can tell whether it is the one on top or has a child pushed over it.
///
/// A `NavigationStack` does **not** fire `onDisappear` on the view a push covers,
/// so a page cannot otherwise notice it has been covered. The pushed page's own
/// `onAppear`/`onDisappear` *do* fire, which makes them the reliable signal.
///
/// This matters because tvOS re-establishes focus by geometry when the stack
/// changes, landing on the topmost focusable control — the hero Play button. The
/// series page treats Play gaining focus as "the user pressed up out of the
/// episode browser" and restores the hero, which collapses the browser and hides
/// the cast with it. Verified on device: that happens as the child is *pushed*,
/// not when it is popped. Knowing a child is on top lets the page ignore focus
/// changes it did not cause, rather than trying to undo them afterwards.
@MainActor
@Observable
public final class DetailStackDepth {
    private var pages: [UUID] = []
    /// Appearance callbacks can repeat or arrive out of order. Membership is
    /// owned by a page identity, never by the number of callbacks received.
    public var depth: Int { pages.count }

    public init() {}

    public func pageAppeared(_ page: UUID) {
        guard !pages.contains(page) else { return }
        pages.append(page)
        HandoffDiagnostics.emit("detail APPEAR page=\(page.uuidString.prefix(8)) depth=\(depth)")
        note("appeared")
    }

    public func pageDismissed(_ page: UUID) {
        guard let index = pages.firstIndex(of: page) else { return }
        pages.remove(at: index)
        HandoffDiagnostics.emit("detail DISAPPEAR page=\(page.uuidString.prefix(8)) depth=\(depth)")
        note("dismissed")
    }

    public func pagesCovering(_ page: UUID) -> Int {
        guard let index = pages.firstIndex(of: page) else { return 0 }
        return pages.count - index - 1
    }

    public func isTopPage(_ page: UUID) -> Bool { pages.last == page }

    // Rate-limited lifecycle diagnostics, including unexpectedly deep real stacks.

    /// Total transitions seen, so a rate-limited line can still report the true
    /// rate rather than only the ones that got logged.
    private var transitions = 0
    private var lastNote = ContinuousClock.now
    private var warnedRunaway = false

    private func note(_ event: String) {  // l10n:content — developer-facing diagnostic
        transitions += 1
        // A real stack is a handful of pages deep. Anything past this is the
        // counter running away, and it is worth one line the moment it happens.
        if depth > 8, !warnedRunaway {
            warnedRunaway = true
            PlozzLog.boot("DetailStackDepth RUNAWAY depth=\(depth) transitions=\(transitions)")
        }
        let now = ContinuousClock.now
        guard lastNote.duration(to: now) >= .seconds(1) else { return }
        lastNote = now
        PlozzLog.boot(
            "DetailStackDepth \(event) depth=\(depth) transitions=\(transitions)"
        )
    }
}
