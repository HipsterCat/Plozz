#if os(iOS)
import SwiftUI
import UIKit
import XCTest

@MainActor
extension XCTestCase {
    @discardableResult
    func captureNativeSheet<Content: View>(
        _ content: Content,
        size: CGSize,
        name: String,
        colorScheme: ColorScheme = .dark
    ) async throws -> UIImage {
        let controller = UIHostingController(rootView: content)
        let previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        controller.overrideUserInterfaceStyle = window.overrideUserInterfaceStyle
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.view.bounds.size.width, size.width, accuracy: 0.5)
        XCTAssertFalse(controller.view.subviews.isEmpty)
        // Hostless package tests cannot reliably use drawHierarchy's render-server path.
        let image = UIGraphicsImageRenderer(size: size).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }
}
#endif
