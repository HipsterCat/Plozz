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

    func updateReflection(
        height: CGFloat, topHeight: CGFloat = 0, leftWidth: CGFloat = 0, rightWidth: CGFloat = 0,
        previewCornerRadius: CGFloat = 0
    ) {
        #if os(iOS)
        let insets = UIEdgeInsets(top: topHeight, left: leftWidth, bottom: height, right: rightWidth)
        guard reflection.insets != insets || reflection.previewCornerRadius != previewCornerRadius else { return }
        reflection.insets = insets
        reflection.previewCornerRadius = previewCornerRadius
        clipsToBounds = insets == .zero
        backgroundColor = previewCornerRadius > 0 || insets != .zero ? .clear : .black
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
        reflection.videoSize = bounds.size
        reflection.picture = (videoRect ?? bounds).intersection(bounds)
        reflection.frame = CGRect(
            x: bounds.minX - reflection.insets.left, y: bounds.minY - reflection.insets.top,
            width: bounds.width + reflection.insets.left + reflection.insets.right,
            height: bounds.height + reflection.insets.top + reflection.insets.bottom
        )
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
        var videoSize: CGSize = .zero {
            didSet { if oldValue != videoSize { setNeedsLayout() } }
        }
        var picture: CGRect = .zero {
            didSet { if oldValue != picture { setNeedsLayout() } }
        }
        var insets: UIEdgeInsets = .zero {
            didSet { if oldValue != insets { setNeedsLayout() } }
        }
        var previewCornerRadius: CGFloat = 0 {
            didSet { if oldValue != previewCornerRadius { setNeedsLayout() } }
        }
        private static let fadeSteps: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1]
        private let topReplicas = VideoPreviewReplicaView()
        private let replicas = VideoPreviewReplicaView()
        private let leftReplicas = VideoPreviewReplicaView()
        private let rightReplicas = VideoPreviewReplicaView()
        private let pictureCrop = CAShapeLayer()
        private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        private let blurMask = CAShapeLayer()
        private let fade = CAGradientLayer()
        private let horizontalFade = CAGradientLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            source.backgroundColor = .black
            source.clipsToBounds = true
            addSubview(topReplicas)
            topReplicas.addSubview(replicas)
            replicas.addSubview(leftReplicas)
            leftReplicas.addSubview(rightReplicas)
            rightReplicas.addSubview(source)
            pictureCrop.fillColor = UIColor.white.cgColor
            blurMask.fillColor = UIColor.white.cgColor
            blurMask.fillRule = .evenOdd
            blur.layer.mask = blurMask
            addSubview(blur)
            fade.startPoint = CGPoint(x: 0.5, y: 0)
            fade.endPoint = CGPoint(x: 0.5, y: 1)
            horizontalFade.startPoint = CGPoint(x: 0, y: 0.5)
            horizontalFade.endPoint = CGPoint(x: 1, y: 0.5)
            fade.mask = horizontalFade
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            topReplicas.frame = CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: videoSize)
            replicas.frame = topReplicas.bounds
            leftReplicas.frame = replicas.bounds
            rightReplicas.frame = leftReplicas.bounds
            source.frame = rightReplicas.bounds
            let reflects = insets != .zero
            let decorates = reflects || previewCornerRadius > 0
            let visiblePicture = decorates ? picture : source.bounds
            isHidden = visiblePicture.isEmpty || visiblePicture.isNull || visiblePicture.isInfinite
            guard !isHidden else { return }
            let translatedPicture = visiblePicture.offsetBy(dx: insets.left, dy: insets.top)
            let left = max(0, translatedPicture.minX)
            let right = max(0, bounds.width - translatedPicture.maxX)
            let top = max(0, translatedPicture.minY)
            let bottom = max(0, bounds.height - translatedPicture.maxY)
            let radius = left > 1 && right > 1 ? previewCornerRadius : 0
            pictureCrop.frame = source.bounds
            pictureCrop.path = UIBezierPath(roundedRect: visiblePicture, cornerRadius: radius).cgPath
            source.layer.mask = decorates ? pictureCrop : nil
            configureReplica(rightReplicas, horizontal: true, edge: visiblePicture.maxX,
                             extent: right, pictureLength: visiblePicture.width, enabled: reflects)
            configureReplica(leftReplicas, horizontal: true, edge: visiblePicture.minX,
                             extent: left, pictureLength: visiblePicture.width, enabled: reflects)
            configureReplica(replicas, horizontal: false, edge: visiblePicture.maxY,
                             extent: bottom, pictureLength: visiblePicture.height, enabled: reflects)
            configureReplica(topReplicas, horizontal: false, edge: visiblePicture.minY,
                             extent: top, pictureLength: visiblePicture.height, enabled: reflects)
            blur.isHidden = !reflects
            let blurScale: CGFloat = 4
            blur.bounds = CGRect(x: 0, y: 0, width: bounds.width / blurScale, height: bounds.height / blurScale)
            blur.center = CGPoint(x: bounds.midX, y: bounds.midY)
            blur.transform = CGAffineTransform(scaleX: blurScale, y: blurScale)
            let blurPath = UIBezierPath(rect: blur.bounds)
            let sharpPicture = CGRect(
                x: translatedPicture.minX / blurScale, y: translatedPicture.minY / blurScale,
                width: translatedPicture.width / blurScale, height: translatedPicture.height / blurScale
            )
            blurPath.append(UIBezierPath(roundedRect: sharpPicture, cornerRadius: radius / blurScale))
            blurMask.frame = blur.bounds
            blurMask.path = blurPath.cgPath
            fade.frame = bounds
            horizontalFade.frame = fade.bounds
            configureFade(fade, before: top, pictureLength: visiblePicture.height, after: bottom)
            configureFade(horizontalFade, before: left, pictureLength: visiblePicture.width, after: right)
            layer.mask = reflects ? fade : nil
        }

        private func configureReplica(
            _ view: VideoPreviewReplicaView, horizontal: Bool, edge: CGFloat,
            extent: CGFloat, pictureLength: CGFloat, enabled: Bool
        ) {
            view.replicaLayer.instanceCount = enabled && extent > 0 ? 2 : 1
            // Stretch only the reflected tile when a narrow picture has wider gutters.
            let scale = max(1, extent / max(1, pictureLength))
            let anchor = (horizontal ? videoSize.width : videoSize.height) / 2
            let translation = (1 + scale) * (edge - anchor)
            view.replicaLayer.instanceTransform = CATransform3DConcat(
                CATransform3DMakeScale(horizontal ? -scale : 1, horizontal ? 1 : -scale, 1),
                CATransform3DMakeTranslation(horizontal ? translation : 0, horizontal ? 0 : translation, 0)
            )
        }

        private func configureFade(_ gradient: CAGradientLayer, before: CGFloat, pictureLength: CGFloat, after: CGFloat) {
            let total = max(1, before + pictureLength + after)
            var locations: [CGFloat] = [0]
            var alphas: [CGFloat] = [before > 0 ? 0 : 1]
            for step in Self.fadeSteps.dropFirst() where before > 0 {
                locations.append(before * step / total)
                alphas.append(step * step)
            }
            locations.append((before + pictureLength) / total)
            alphas.append(1)
            for step in Self.fadeSteps.dropFirst() where after > 0 {
                locations.append((before + pictureLength + after * step) / total)
                alphas.append((1 - step) * (1 - step))
            }
            gradient.locations = locations.map { NSNumber(value: Double($0)) }
            gradient.colors = alphas.map { UIColor.white.withAlphaComponent($0).cgColor }
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
