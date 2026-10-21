#if canImport(UIKit)
import Observation
import UIKit

/// Crops only the engine's surface. AVKit's external/PiP presentation keeps
/// owning its own sizing, and no video frames are copied or decoded here.
final class VideoPresentationView: UIView {
    private var engine: (any VideoEngine)?
    private var surface: UIView?
    private var zoom = PlayerVideoZoom()
    private var aspectRatio: Double?
    private var fitsInsideSafeArea = false
    private(set) var fitBounds: CGRect?
    weak var subtitleViewport: VideoSubtitleViewport? {
        didSet { subtitleViewport?.attachVideoView(self) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(_ engine: any VideoEngine) {
        let output = engine.makeVideoOutputView()
        self.engine = engine
        guard output.superview !== self else { return }
        if surface?.superview === self { surface?.removeFromSuperview() }
        output.removeFromSuperview()
        output.autoresizingMask = []
        output.isUserInteractionEnabled = false
        surface = output
        addSubview(output)
        setNeedsLayout()
    }

    func update(zoom: PlayerVideoZoom, fitsInsideSafeArea: Bool = false) {
        let ratio = engine?.videoAspectRatio
        let needsUpdate = self.fitsInsideSafeArea != fitsInsideSafeArea
            || aspectRatio != ratio || self.zoom != zoom
        self.zoom = zoom
        aspectRatio = ratio
        self.fitsInsideSafeArea = fitsInsideSafeArea
        guard needsUpdate || fitBounds != resolvedFitBounds else { return }
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
        subtitleViewport?.scheduleUpdate()
    }

    private var resolvedFitBounds: CGRect? {
        #if os(iOS)
        guard fitsInsideSafeArea,
              (engine as? any PictureInPicturePresentingEngine)?.continuesPlaybackInBackground != true
        else { return nil }
        var safe = bounds.inset(by: safeAreaInsets)
        if let window {
            // SwiftUI's ignoresSafeArea can zero the view's insets; the current
            // window still describes the physical cutout and home-indicator area.
            let windowSafe = convert(window.bounds.inset(by: window.safeAreaInsets), from: window)
            safe = safe.intersection(windowSafe)
        }
        if bounds.width > bounds.height {
            // Landscape video can extend behind the home indicator; only the
            // horizontal cutout insets should constrain the fitted picture.
            safe = CGRect(x: safe.minX, y: bounds.minY, width: safe.width, height: bounds.height)
        }
        return safe
        #else
        return nil
        #endif
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        aspectRatio = engine?.videoAspectRatio
        fitBounds = resolvedFitBounds
        guard let surface, surface.superview === self else { return }
        let contentBounds = CGRect(origin: .zero, size: bounds.size)
        let center = zoom.surfaceCenter(in: bounds, fitBounds: fitBounds)
        let scale = zoom.scaleFactors(in: bounds, aspectRatio: aspectRatio, fitBounds: fitBounds)
        let transform = CGAffineTransform(scaleX: scale.dx, y: scale.dy)
        if surface.bounds != contentBounds || surface.center != center || surface.transform != transform {
            UIView.performWithoutAnimation {
                surface.transform = .identity
                surface.bounds = contentBounds
                surface.center = center
                surface.transform = transform
                surface.layoutIfNeeded()
            }
        }
        subtitleViewport?.scheduleUpdate()
    }

    var videoRect: CGRect? { zoom.videoRect(in: bounds, aspectRatio: aspectRatio, fitBounds: fitBounds) }
    var sourceAspectRatio: Double? { aspectRatio }
}

/// Shares the rendered picture with a separately laid-out subtitle overlay,
/// without moving ordinary captions or assuming both views have the same origin.
@MainActor
@Observable
final class VideoSubtitleViewport {
    private(set) var videoRect: CGRect?
    @ObservationIgnored private weak var videoView: VideoPresentationView?
    @ObservationIgnored private weak var subtitleView: UIView?
    @ObservationIgnored private var updateScheduled = false

    func attachVideoView(_ view: VideoPresentationView) {
        videoView = view
        scheduleUpdate()
    }

    func attachSubtitleView(_ view: UIView) {
        subtitleView = view
        scheduleUpdate()
    }

    func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        // Representable updates/layout must not synchronously publish into
        // the SwiftUI graph that is currently placing these views.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            let rect: CGRect?
            if let videoView = self.videoView, let subtitleView = self.subtitleView,
               let window = videoView.window, subtitleView.window === window {
                rect = videoView.videoRect.map { videoView.convert($0, to: subtitleView) }
            } else {
                rect = nil
            }
            if self.videoRect != rect { self.videoRect = rect }
        }
    }
}
#endif
