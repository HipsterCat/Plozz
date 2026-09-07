#if DEBUG
import Foundation
import Observation

public struct LiveTVPreviewRequest: Equatable, Sendable {
    public let channelID: String
    public let revision: UInt64
    public let focusedAt: ContinuousClock.Instant
}

/// Focus requests are committed only after the view's cancellable settling delay.
/// Opening or closing the guide changes presentation, not the active channel.
@MainActor
@Observable
public final class LiveTVPreviewController {
    public static let settlingDelay: Duration = .milliseconds(600)

    public private(set) var isExpanded = false
    public private(set) var followsFocus: Bool
    public private(set) var pendingRequest: LiveTVPreviewRequest?
    public private(set) var focusRestoreRequest = 0
    private let model: LiveTVPrototypeModel
    private var focusedChannelID: String?
    private var browsingActive = true
    private var revision: UInt64 = 0

    public init(model: LiveTVPrototypeModel, followsFocus: Bool = true) {
        self.model = model
        self.followsFocus = followsFocus
    }

    public func focus(_ channelID: String?) {
        guard focusedChannelID != channelID else { return }
        focusedChannelID = channelID
        schedulePreview()
    }

    public func setBrowsingActive(_ active: Bool) {
        guard browsingActive != active else { return }
        browsingActive = active
        schedulePreview()
    }

    public func setFollowsFocus(_ enabled: Bool) {
        guard followsFocus != enabled else { return }
        followsFocus = enabled
        schedulePreview()
    }

    @discardableResult
    public func commitPreview(_ request: LiveTVPreviewRequest) -> Bool {
        guard pendingRequest == request, browsingActive, followsFocus, !isExpanded else { return false }
        pendingRequest = nil
        guard model.visibleChannels.contains(where: { $0.id == request.channelID }) else { return false }
        model.tune(request.channelID)
        return !model.tuneFailed
    }

    public func watch(_ channelID: String) {
        cancelPendingPreview()
        model.tune(channelID)
        guard !model.tuneFailed else { return }
        followsFocus = false
        isExpanded = true
    }

    public func returnToGuide() {
        guard isExpanded else { return }
        isExpanded = false
        focusRestoreRequest &+= 1
    }

    public func playbackEnded() {
        isExpanded = false
        cancelPendingPreview()
    }

    public func stop() {
        cancelPendingPreview()
        focusedChannelID = nil
        isExpanded = false
        model.stop()
    }

    private func schedulePreview() {
        cancelPendingPreview()
        guard browsingActive, followsFocus, !isExpanded,
              let focusedChannelID, focusedChannelID != model.playingChannelID else { return }
        pendingRequest = LiveTVPreviewRequest(
            channelID: focusedChannelID, revision: revision, focusedAt: ContinuousClock.now
        )
    }

    private func cancelPendingPreview() {
        revision &+= 1
        pendingRequest = nil
    }
}
#endif
