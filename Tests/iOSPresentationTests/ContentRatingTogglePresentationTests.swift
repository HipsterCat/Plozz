#if os(iOS)
import CoreModels
import PlozzCoreUI
import FeatureSettings
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class ContentRatingTogglePresentationTests: XCTestCase {
    func testNativeToggleKeepsExamplesWhenOffAndFitsPhoneAndAccessibleLayouts() async throws {
        let suite = "ContentRatingTogglePresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ContentRatingSettingsStore(defaults: defaults)
        let model = ContentRatingSettingsModel(store: store)
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        for (width, textSize) in [(390.0, DynamicTypeSize.large), (320.0, .large), (390.0, .accessibility3)] {
            model.showsRatings = true
            window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = UIHostingController(rootView:
                ScrollView {
                    SettingsSectionGroup {
                        ContentRatingToggle(model: model)
                    }
                }
                .settingsPageSurface()
                .environment(\.themePalette, .dark)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, textSize)
                .environment(\.plozzShowsContentRatings, false)
            )
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            let toggle = try XCTUnwrap(descendants(of: window).compactMap { $0 as? UISwitch }.first)
            XCTAssertTrue(toggle.isOn)
            toggle.setOn(false, animated: false)
            toggle.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(model.showsRatings)
            XCTAssertFalse(store.load())
            let bounds = toggle.convert(toggle.bounds, to: window)
            XCTAssertGreaterThanOrEqual(bounds.minX, 0)
            XCTAssertLessThanOrEqual(bounds.maxX, width)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Content rating toggle off \(width) \(textSize)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.customWords = ["PG-13", "R"]
            request.minimumTextHeight = 0.005
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
            XCTAssertTrue(text.contains("Show content ratings"), text)
            XCTAssertTrue(text.contains("PG-13"), "Examples must remain visible when disabled: \(text)")
            if width == 390, textSize == .large {
                let lines = try XCTUnwrap(request.results)
                let title = try XCTUnwrap(lines.first { $0.topCandidates(1).first?.string.contains("Show") == true })
                let example = try XCTUnwrap(lines.first { $0.topCandidates(1).first?.string.contains("PG-13") == true })
                XCTAssertEqual(title.boundingBox.midY, example.boundingBox.midY, accuracy: 0.012,
                               "Normal phone layout should use a single line.")
            }
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
#endif
