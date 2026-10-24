#if canImport(SwiftUI)
import SwiftUI

struct PlozzChannelPixelMascot: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outlines: [[CGPoint]] = [
            [
                .init(x: 6, y: 6), .init(x: 26, y: 6), .init(x: 26, y: 7), .init(x: 28, y: 7),
                .init(x: 28, y: 8), .init(x: 29, y: 8), .init(x: 29, y: 10), .init(x: 30, y: 10),
                .init(x: 30, y: 26), .init(x: 29, y: 26), .init(x: 29, y: 28), .init(x: 28, y: 28),
                .init(x: 28, y: 29), .init(x: 26, y: 29), .init(x: 26, y: 30), .init(x: 6, y: 30),
                .init(x: 6, y: 29), .init(x: 4, y: 29), .init(x: 4, y: 28), .init(x: 3, y: 28),
                .init(x: 3, y: 26), .init(x: 2, y: 26), .init(x: 2, y: 10), .init(x: 3, y: 10),
                .init(x: 3, y: 8), .init(x: 4, y: 8), .init(x: 4, y: 7), .init(x: 6, y: 7)
            ],
            [
                .init(x: 6, y: 8), .init(x: 26, y: 8), .init(x: 26, y: 9), .init(x: 27, y: 9),
                .init(x: 27, y: 10), .init(x: 28, y: 10), .init(x: 28, y: 26), .init(x: 27, y: 26),
                .init(x: 27, y: 27), .init(x: 26, y: 27), .init(x: 26, y: 28), .init(x: 6, y: 28),
                .init(x: 6, y: 27), .init(x: 5, y: 27), .init(x: 5, y: 26), .init(x: 4, y: 26),
                .init(x: 4, y: 10), .init(x: 5, y: 10), .init(x: 5, y: 9), .init(x: 6, y: 9)
            ],
            [
                .init(x: 9, y: 2), .init(x: 11, y: 2), .init(x: 11, y: 3), .init(x: 12, y: 3),
                .init(x: 12, y: 4), .init(x: 13, y: 4), .init(x: 13, y: 5), .init(x: 14, y: 5),
                .init(x: 14, y: 4), .init(x: 15, y: 4), .init(x: 15, y: 3), .init(x: 16, y: 3),
                .init(x: 16, y: 2), .init(x: 18, y: 2), .init(x: 18, y: 4), .init(x: 17, y: 4),
                .init(x: 17, y: 5), .init(x: 16, y: 5), .init(x: 16, y: 6), .init(x: 11, y: 6),
                .init(x: 11, y: 5), .init(x: 10, y: 5), .init(x: 10, y: 4), .init(x: 9, y: 4)
            ]
        ]
        for points in outlines {
            path.addLines(points)
            path.closeSubpath()
        }
        for eyeX: CGFloat in [12, 17] {
            path.addRect(CGRect(x: eyeX, y: 14, width: 3, height: 1))
            path.addRect(CGRect(x: eyeX + 1, y: 15, width: 2, height: 1))
            path.addRect(CGRect(x: eyeX, y: 16, width: 2, height: 1))
            path.addRect(CGRect(x: eyeX, y: 17, width: 3, height: 1))
        }
        path.addRect(CGRect(x: 13, y: 20, width: 1, height: 1))
        path.addRect(CGRect(x: 18, y: 20, width: 1, height: 1))
        path.addRect(CGRect(x: 14, y: 21, width: 4, height: 1))
        let scale = min(rect.width, rect.height) / 32
        return path.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 16 * scale, ty: rect.midY - 16 * scale
        ))
    }
}
#endif
