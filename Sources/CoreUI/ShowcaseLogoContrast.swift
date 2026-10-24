#if canImport(UIKit)
import UIKit

/// An optional, pre-rendered shadow lift. Selection never decodes or filters pixels.
struct ShowcaseLogoContrast: @unchecked Sendable {
    let image: UIImage
    let originalDarkInk: SIMD3<Double>
    let liftedDarkInk: SIMD3<Double>

    func improvesContrast(on background: SIMD3<Double>) -> Bool {
        let original = Self.contrast(originalDarkInk, background)
        let lifted = Self.contrast(liftedDarkInk, background)
        return original < 3 && lifted >= original + 0.75
    }

    static func isDarkInk(_ rgb: SIMD3<Double>) -> Bool {
        max(rgb.x, rgb.y, rgb.z) < 0.65 && luminance(rgb) < 0.35
    }

    static func lifted(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let luma = luminance(rgb)
        guard luma < 0.72 else { return rgb }
        let target = 0.56 + luma * (1 - 0.56 / 0.72)
        // Stop at the available colour headroom rather than mixing in white to
        // reach the luminance target. Uniform gain preserves hue and saturation.
        let peak = max(rgb.x, rgb.y, rgb.z)
        let gain = peak > 0 && luma > 0 ? max(1, min(0.9 / peak, target / luma)) : 1
        return rgb * gain
    }

    static func luminance(_ rgb: SIMD3<Double>) -> Double {
        0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
    }

    static func contrast(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        func relativeLuminance(_ rgb: SIMD3<Double>) -> Double {
            luminance(SIMD3(linear(rgb.x), linear(rgb.y), linear(rgb.z)))
        }
        let a = relativeLuminance(lhs), b = relativeLuminance(rhs)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
#endif
