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
    #if os(iOS)
    private let reflection = VideoPreviewReflectionView()
    #endif
    private(set) var fitBounds: CGRect?
    weak var subtitleViewport: VideoSubtitleViewport? {
        didSet { subtitleViewport?.attachVideoView(self) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        #if os(iOS)
        addSubview(reflection)
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(_ engine: any VideoEngine) {
        let output = engine.makeVideoOutputView()
        self.engine = engine
        guard output.superview !== surfaceHost else { return }
        if surface?.superview === surfaceHost { surface?.removeFromSuperview() }
        output.removeFromSuperview()
        output.autoresizingMask = []
        output.isUserInteractionEnabled = false
        surface = output
        surfaceHost.addSubview(output)
        setNeedsLayout()
    }

    private var surfaceHost: UIView {
        #if os(iOS)
        reflection.source
        #else
        self
        #endif
    }

    func updateReflection(height: CGFloat, topHeight: CGFloat = 0) {
        #if os(iOS)
        guard reflection.reflectionHeight != height || reflection.topReflectionHeight != topHeight else { return }
        reflection.reflectionHeight = height
        reflection.topReflectionHeight = topHeight
        clipsToBounds = height <= 0 && topHeight <= 0
        setNeedsLayout()
        #endif
    }

    func update(zoom: PlayerVideoZoom, aspectRatio: Double? = nil, fitsInsideSafeArea: Bool = false) {
        let ratio = aspectRatio ?? engine?.videoAspectRatio
        let needsUpdate = self.fitsInsideSafeArea != fitsInsideSafeArea
            || self.aspectRatio != ratio || self.zoom != zoom
        self.zoom = zoom
        self.aspectRatio = ratio
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
        #if os(iOS)
        reflection.videoHeight = bounds.height
        reflection.frame = CGRect(x: bounds.minX, y: bounds.minY - reflection.topReflectionHeight,
                                  width: bounds.width,
                                  height: bounds.height + reflection.reflectionHeight + reflection.topReflectionHeight)
        reflection.pictureTop = max(0, videoRect?.minY ?? 0)
        reflection.pictureBottom = min(bounds.height, videoRect?.maxY ?? bounds.height)
        reflection.pictureHeight = min(bounds.height, videoRect?.height ?? bounds.height)
        reflection.layoutIfNeeded()
        #endif
        guard let surface, surface.superview === surfaceHost else { return }
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

    #if os(iOS)
    /// Replicates the existing compositor surface, not a second player or decoded frame.
    private final class VideoPreviewReflectionView: UIView {
        let source = UIView()
        var videoHeight: CGFloat = 0 {
            didSet { if oldValue != videoHeight { setNeedsLayout() } }
        }
        var pictureBottom: CGFloat = 0 {
            didSet { if oldValue != pictureBottom { setNeedsLayout() } }
        }
        var pictureTop: CGFloat = 0 {
            didSet { if oldValue != pictureTop { setNeedsLayout() } }
        }
        var pictureHeight: CGFloat = 0 {
            didSet { if oldValue != pictureHeight { setNeedsLayout() } }
        }
        var reflectionHeight: CGFloat = 0 {
            didSet { if oldValue != reflectionHeight { setNeedsLayout() } }
        }
        var topReflectionHeight: CGFloat = 0 {
            didSet { if oldValue != topReflectionHeight { setNeedsLayout() } }
        }
        private static let fadeSteps: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1]
        private let topReplicas = VideoPreviewReplicaView()
        private let replicas = VideoPreviewReplicaView()
        private let crop = CALayer()
        private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        private let topBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        private let fade = CAGradientLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            source.backgroundColor = .black
            source.clipsToBounds = true
            addSubview(topReplicas)
            topReplicas.addSubview(replicas)
            replicas.addSubview(source)
            crop.backgroundColor = UIColor.white.cgColor
            replicas.layer.mask = crop
            addSubview(blur)
            addSubview(topBlur)
            layer.mask = fade
            fade.startPoint = CGPoint(x: 0.5, y: 0)
            fade.endPoint = CGPoint(x: 0.5, y: 1)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            topReplicas.frame = CGRect(x: 0, y: topReflectionHeight, width: bounds.width, height: videoHeight)
            replicas.frame = topReplicas.bounds
            source.frame = replicas.bounds
            let height = min(reflectionHeight, pictureHeight)
            let topHeight = min(topReflectionHeight, pictureHeight)
            let total = max(1, topHeight + videoHeight + height)
            replicas.replicaLayer.instanceCount = height > 0 ? 2 : 1
            topReplicas.replicaLayer.instanceCount = topHeight > 0 ? 2 : 1
            blur.isHidden = height <= 0
            topBlur.isHidden = topHeight <= 0
            replicas.replicaLayer.instanceTransform = CATransform3DConcat(
                CATransform3DMakeScale(1, -1, 1),
                CATransform3DMakeTranslation(0, pictureBottom, 0)
            )
            topReplicas.replicaLayer.instanceTransform = CATransform3DConcat(
                CATransform3DMakeScale(1, -1, 1),
                CATransform3DMakeTranslation(0, pictureTop - videoHeight, 0)
            )
            crop.frame = CGRect(x: 0, y: 0, width: bounds.width, height: videoHeight + height)
            let blurScale: CGFloat = 4
            blur.bounds = CGRect(x: 0, y: 0, width: bounds.width / blurScale, height: height / blurScale)
            blur.center = CGPoint(x: bounds.midX, y: topReflectionHeight + videoHeight + height / 2)
            blur.transform = CGAffineTransform(scaleX: blurScale, y: blurScale)
            topBlur.bounds = CGRect(x: 0, y: 0, width: bounds.width / blurScale, height: topHeight / blurScale)
            topBlur.center = CGPoint(x: bounds.midX, y: topReflectionHeight - topHeight / 2)
            topBlur.transform = CGAffineTransform(scaleX: blurScale, y: blurScale)
            // Fade both the replica and its blur to the real background, not a flat color.
            fade.frame = CGRect(x: 0, y: topReflectionHeight - topHeight, width: bounds.width, height: total)
            var locations: [CGFloat] = [0]
            var alphas: [CGFloat] = [topHeight > 0 ? 0 : 1]
            for step in Self.fadeSteps.dropFirst() where topHeight > 0 {
                locations.append(topHeight * step / total)
                alphas.append(step * step)
            }
            locations.append((topHeight + videoHeight) / total)
            alphas.append(1)
            for step in Self.fadeSteps.dropFirst() where height > 0 {
                locations.append((topHeight + videoHeight + height * step) / total)
                alphas.append((1 - step) * (1 - step))
            }
            fade.locations = locations.map { NSNumber(value: Double($0)) }
            fade.colors = alphas.map { UIColor.white.withAlphaComponent($0).cgColor }
            layer.mask = height > 0 || topHeight > 0 ? fade : nil
            CATransaction.commit()
        }
    }

    private final class VideoPreviewReplicaView: UIView {
        override class var layerClass: AnyClass { CAReplicatorLayer.self }
        var replicaLayer: CAReplicatorLayer { layer as! CAReplicatorLayer }
    }
    #endif

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
