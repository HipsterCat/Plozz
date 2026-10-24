#if canImport(SwiftUI)
import SwiftUI

/// Decorative startup mark. Its animation lifetime belongs to this leaf, never
/// to the app's startup work or readiness state.
public struct PlozzStartupLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let onIntroCompleted: (() -> Void)?

    public init(onIntroCompleted: (() -> Void)? = nil) {
        self.onIntroCompleted = onIntroCompleted
    }

    public var body: some View {
        PlozzStartupLogoContent(
            reduceMotion: reduceMotion, scenePhase: scenePhase,
            expression: PlozzStartupLogoMotion.shouldAnimate(reduceMotion: reduceMotion, scenePhase: scenePhase)
                ? PlozzStartupExpression.currentLaunch : .wink,
            onIntroCompleted: onIntroCompleted
        )
    }
}

struct PlozzStartupLogoContent: View {
    let reduceMotion: Bool
    let scenePhase: ScenePhase
    var expression: PlozzStartupExpression = .wink
    let onIntroCompleted: (() -> Void)?
    @State private var didCompleteIntro = false

    var body: some View {
        Group {
            if !PlozzStartupLogoMotion.shouldAnimate(reduceMotion: reduceMotion, scenePhase: scenePhase) {
                PlozzStartupLogoArtwork(pose: .rest)
            } else {
                Color.clear
                    .keyframeAnimator(initialValue: PlozzStartupLogoMotion.Pose.rest) { _, pose in
                        PlozzStartupLogoArtwork(pose: pose, expression: expression)
                            .onChange(of: pose.introCompleted, initial: true) { _, completed in
                                if completed == 1 { completeIntro() }
                            }
                    } keyframes: { _ in
                        PlozzStartupLogoMotion.keyframes
                    }
            }
        }
        #if os(tvOS)
        .frame(width: 192, height: 192)
        #else
        .frame(width: 128, height: 128)
        #endif
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onChange(of: reduceMotion, initial: true) { _, reduceMotion in
            if reduceMotion { completeIntro() }
        }
    }

    private func completeIntro() {
        guard !didCompleteIntro else { return }
        didCompleteIntro = true
        onIntroCompleted?()
    }
}

enum PlozzStartupExpression: String, CaseIterable {
    case wink, delight, surprise

    // A view remount or foreground transition must not advance the launch rotation.
    static let currentLaunch = nextLaunch(defaults: .standard)
    private static let defaultsKey = "com.plozz.lastStartupExpression"

    var next: Self {
        switch self {
        case .wink: .delight
        case .delight: .surprise
        case .surprise: .wink
        }
    }

    var assetName: String {
        switch self {
        case .wink: "PlozzStartupWink"
        case .delight: "PlozzStartupDelight"
        case .surprise: "PlozzStartupSurprise"
        }
    }

    static func nextLaunch(defaults: UserDefaults) -> Self {
        let previous = defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:))
        let expression = previous?.next ?? .wink
        defaults.set(expression.rawValue, forKey: defaultsKey)
        return expression
    }
}

struct PlozzStartupLogoArtwork: View {
    let pose: PlozzStartupLogoMotion.Pose
    var expression: PlozzStartupExpression = .wink

    var body: some View {
        ZStack {
            face("PlozzStartupSmile")
            face(expression.assetName)
                .opacity(pose.primaryOpacity)
            face(expression.next.assetName)
                .opacity(pose.secondaryOpacity)
        }
        .rotationEffect(.degrees(pose.tilt + pose.turn))
    }

    private func face(_ name: String) -> some View {
        Image(name, bundle: .module)
            .renderingMode(.original)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
    }
}

enum PlozzStartupLogoMotion {
    static let minimumDisplayDuration = 0.7

    static func shouldAnimate(reduceMotion: Bool, scenePhase: ScenePhase) -> Bool {
        !reduceMotion && scenePhase == .active
    }

    struct Pose: Equatable {
        var primaryOpacity = 0.0
        var secondaryOpacity = 0.0
        var tilt = 0.0
        var turn = 0.0
        var introCompleted = 0.0

        static let rest = Pose()
    }

    // All tracks last eight seconds. The final full turn is visually identical
    // to zero, so repeating never rewinds. Keeping the smile opaque underneath
    // each expression also prevents the shared pixel outline from fading.
    @KeyframesBuilder<Pose>
    static var keyframes: some Keyframes<Pose> {
        KeyframeTrack(\.primaryOpacity) {
            LinearKeyframe(0, duration: 0.25)
            LinearKeyframe(1, duration: 0.15)
            LinearKeyframe(1, duration: 0.55)
            LinearKeyframe(0, duration: 0.15)
            LinearKeyframe(0, duration: 6.9)
        }
        KeyframeTrack(\.introCompleted) {
            LinearKeyframe(0, duration: minimumDisplayDuration)
            MoveKeyframe(1)
            LinearKeyframe(1, duration: 8 - minimumDisplayDuration)
        }
        KeyframeTrack(\.secondaryOpacity) {
            LinearKeyframe(0, duration: 1.7)
            LinearKeyframe(1, duration: 0.15)
            LinearKeyframe(1, duration: 3.95)
            LinearKeyframe(0, duration: 0.2)
            LinearKeyframe(0, duration: 2)
        }
        KeyframeTrack(\.tilt) {
            LinearKeyframe(0, duration: 0.8)
            CubicKeyframe(-6, duration: 0.35, startVelocity: 0, endVelocity: 0)
            LinearKeyframe(-6, duration: 0.55)
            CubicKeyframe(0, duration: 0.35, startVelocity: 0, endVelocity: 0)
            LinearKeyframe(0, duration: 5.95)
        }
        KeyframeTrack(\.turn) {
            LinearKeyframe(0, duration: 3.5)
            CubicKeyframe(-12, duration: 0.25, startVelocity: 0, endVelocity: 0)
            CubicKeyframe(360, duration: 0.9, startVelocity: 0, endVelocity: 0)
            LinearKeyframe(360, duration: 3.35)
        }
    }
}
#endif
