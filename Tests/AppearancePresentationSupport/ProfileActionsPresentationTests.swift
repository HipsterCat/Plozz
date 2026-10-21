import CoreModels
import CoreUI
import FeatureProfiles
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class ProfileActionsPresentationTests: XCTestCase {
    func testSettingsLabelsKeepIconAndTitleColumnsAcrossSymbolWidths() throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let renderer = ImageRenderer(content:
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ProfileSettingsCategory.allCases) { category in
                            Group {
                                #if os(tvOS)
                                SettingsRowLabel(
                                    icon: category.symbol,
                                    title: Text(verbatim: "Alignment")
                                        .foregroundStyle(Color(red: 1, green: 0, blue: 0))
                                )
                                .environment(\.settingsRowIsFocused, true)
                                .environment(\.settingsRowFocusForeground, Color(red: 0, green: 1, blue: 0))
                                #else
                                Label {
                                    Text(verbatim: "Alignment").background(Color(red: 1, green: 0, blue: 0))
                                } icon: {
                                    Image(systemName: category.symbol).background(Color(red: 0, green: 1, blue: 0))
                                }
                                #endif
                            }
                            .frame(width: 500, height: 100, alignment: .leading)
                        }
                    }
                    .labelStyle(SettingsIconLabelStyle())
                    .environment(\.layoutDirection, direction)
                    .environment(\.dynamicTypeSize, textSize)
                    .environment(\.themePalette, .dark)
                    .background(Color.black)
                )
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                let attachment = XCTAttachment(image: UIImage(cgImage: image))
                attachment.name = "Settings columns \(direction) \(textSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let rows = try columnBounds(in: image, rowHeight: 100)
                let reference = try XCTUnwrap(rows.first)
                for (index, row) in rows.enumerated() {
                    XCTAssertEqual(row.icon.midX, reference.icon.midX, accuracy: 1,
                                   "\(ProfileSettingsCategory.allCases[index]) icon center")
                    XCTAssertEqual(
                        direction == .leftToRight ? row.title.minX : row.title.maxX,
                        direction == .leftToRight ? reference.title.minX : reference.title.maxX,
                        accuracy: 1, "\(ProfileSettingsCategory.allCases[index]) title column"
                    )
                }
            }
        }
    }

    private func columnBounds(in image: CGImage, rowHeight: Int) throws -> [(icon: CGRect, title: CGRect)] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (0..<ProfileSettingsCategory.allCases.count).map { row in
            var icon = CGRect.null
            var title = CGRect.null
            for y in (row * rowHeight)..<((row + 1) * rowHeight) {
                for x in 0..<image.width {
                    let offset = (y * image.width + x) * 4
                    let point = CGRect(x: x, y: y, width: 1, height: 1)
                    if bytes[offset] > 200, bytes[offset + 1] < 30, bytes[offset + 2] < 30 {
                        title = title.union(point)
                    }
                    if bytes[offset + 1] > 200, bytes[offset] < 30, bytes[offset + 2] < 30 {
                        icon = icon.union(point)
                    }
                }
            }
            XCTAssertFalse(icon.isNull)
            XCTAssertFalse(title.isNull)
            return (icon, title)
        }
    }

    func testProfileActionsKeepDeviceScopeAndAlignedSeparateGroups() async throws {
        #if os(tvOS)
        let cases: [(CGSize, DynamicTypeSize)] = [(CGSize(width: 1920, height: 1080), .large)]
        #else
        let cases: [(CGSize, DynamicTypeSize)] = [
            (CGSize(width: 320, height: 568), .large),
            (CGSize(width: 390, height: 844), .accessibility3),
            (CGSize(width: 768, height: 1024), .large)
        ]
        #endif
        for (size, textSize) in cases {
            try await withWindow(size: size, content: fixture().environment(\.dynamicTypeSize, textSize)) { window in
                let labels = try await captureAllText(window, name: "profile-settings-\(Int(size.width))-\(textSize)")
                let text = labels.map(\.text).joined(separator: " ").replacingOccurrences(of: "- ", with: "-")
                for expected in ["Appearance", "Profile Lock", "Kids Profile", "Automatically Sign In",
                                 "Sign in to the last-used profile automatically on this device.", "Delete Profile"] {
                    XCTAssertTrue(text.contains(expected), "Missing or clipped \(expected): \(text)")
                }
                XCTAssertFalse(labels.contains { $0.text == "THIS DEVICE" || $0.text == "This Device" })
                if !textSize.isAccessibilitySize {
                    let appearance = try frame("Appearance", in: labels)
                    let lock = try frame("Profile Lock", in: labels)
                    let kids = try frame("Kids Profile", in: labels)
                    let signIn = try frame("Automatically Sign In", in: labels)
                    let delete = try frame("Delete Profile", in: labels)
                    for other in [lock, kids, delete] {
                        XCTAssertEqual(other.minX, appearance.minX, accuracy: 5,
                                       "Management titles must share one leading keyline, including Delete.")
                    }
                    XCTAssertLessThan(appearance.minY, lock.minY)
                    XCTAssertLessThan(lock.minY, kids.minY)
                    XCTAssertLessThan(kids.maxY, signIn.minY)
                    XCTAssertLessThan(signIn.maxY, delete.minY)
                    #if os(iOS)
                    XCTAssertLessThan(kids.maxY - appearance.minY, 200,
                                      "Do not combine padded SettingsRowLabel rows with group-owned insets.")
                    #endif
                }
            }
        }
    }

    func testLockedAndRestrictedProfilesDoNotOfferAutomaticSignIn() async throws {
        var locked = profile
        locked.lock = try XCTUnwrap(ProfileLock.make(pin: "1234", iterations: 10))
        for sealedByLock in [true, false] {
            let content = fixture(
                profile: sealedByLock ? locked : profile,
                isUnlocked: !sealedByLock,
                restricted: !sealedByLock
            )
            try await withWindow(content: content) { window in
                let text = try await captureAllText(window, name: "profile-settings-sealed-\(sealedByLock)")
                    .map(\.text).joined(separator: " ")
                XCTAssertFalse(text.contains("Automatically Sign In"), text)
                XCTAssertFalse(text.contains("Delete Profile"), text)
                if sealedByLock {
                    XCTAssertTrue(text.contains(String(localized: ProfileLockCopy.unlockToEdit)), text)
                } else {
                    XCTAssertTrue(text.contains("Appearance"), text)
                    XCTAssertFalse(text.contains("Profile Lock"), text)
                    XCTAssertFalse(text.contains("Kids Profile"), text)
                }
            }
        }
    }

    func testProfileSettingsKeepAutomaticSignInErrorsVisible() async throws {
        try await withWindow(content: fixture(error: "Could not save automatic sign-in.")) { window in
            let text = try await captureAllText(window, name: "profile-settings-signin-error")
                .map(\.text).joined(separator: " ")
            XCTAssertTrue(text.contains("Could not save automatic sign-in."), text)
        }
    }

    private var profile: Profile {
        Profile(id: "profile-presentation", name: "Sample profile", avatarSymbol: "person.fill")
    }

    private func fixture(
        profile: Profile? = nil, isUnlocked: Bool = true, restricted: Bool = false,
        error: LocalizedStringResource? = nil
    ) -> some View {
        let actions = ProfileActionsList(
            profile: profile ?? self.profile, syncEnabled: false,
            offersPlexPINReuse: true, hasParentalPIN: true,
            restrictedActionsSealed: restricted, groupsActions: true,
            automaticSignIn: AutomaticSignInSettings(isEnabled: .constant(false), error: error),
            onEditAppearance: {}, onSetLock: { _ in }, onSetKids: { _ in },
            onDelete: {}, isUnlocked: isUnlocked
        )
        return Group {
            #if os(tvOS)
            ScrollView {
                actions.frame(width: 960).padding(32)
            }
            #else
            List {
                actions
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            #endif
        }
        #if os(tvOS)
        .background { SettingsPageBackground() }
        #else
        .settingsPageSurface()
        #endif
    }

    private struct RecognizedLabel {
        let text: String
        let frame: CGRect
    }

    private func frame(_ prefix: String, in labels: [RecognizedLabel]) throws -> CGRect {
        try XCTUnwrap(labels.first { $0.text.hasPrefix(prefix) }, "Missing \(prefix)").frame
    }

    private func withWindow(
        size: CGSize? = nil, content: some View, exercise: (UIWindow) async throws -> Void
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        if let size { window.frame = CGRect(origin: .zero, size: size) }
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: content
            .environment(\.themePalette, .dark)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US")))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await settle(window)
        #if os(tvOS)
        XCTAssertNotNil(UIFocusSystem.focusSystem(for: window)?.focusedItem)
        #endif
        try await exercise(window)
    }

    private func captureAllText(_ window: UIWindow, name: String) async throws -> [RecognizedLabel] {
        let scroll = try XCTUnwrap(scrollViews(in: window).first)
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
        var labels: [RecognizedLabel] = []
        for page in 0..<12 {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name)-\(page)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            for observation in request.results ?? [] {
                guard let text = observation.topCandidates(1).first?.string else { continue }
                let bounds = observation.boundingBox
                let frame = CGRect(
                    x: bounds.minX * window.bounds.width,
                    y: (1 - bounds.maxY) * window.bounds.height + scroll.contentOffset.y,
                    width: bounds.width * window.bounds.width,
                    height: bounds.height * window.bounds.height
                )
                if !labels.contains(where: { $0.text == text && abs($0.frame.minY - frame.minY) < 5 }) {
                    labels.append(RecognizedLabel(text: text, frame: frame))
                }
            }
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y >= bottom - 1 {
                return labels.sorted { $0.frame.minY < $1.frame.minY }
            }
            scroll.setContentOffset(CGPoint(x: 0, y: min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.65)),
                                    animated: false)
            try await settle(window)
        }
        XCTFail("The profile settings content did not finish within twelve screenfuls.")
        return labels
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        if let scroll = view as? UIScrollView { return [scroll] }
        return view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        window.layoutIfNeeded()
    }
}
