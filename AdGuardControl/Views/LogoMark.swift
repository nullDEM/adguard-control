import SwiftUI

/// Znak aplikacji: tarcza z włączonym przełącznikiem (wersja wektorowa z `branding/final`).
struct LogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Współrzędne z siatki 256 × 256; znak zajmuje 40…216 × 20…238.
        let side = min(rect.width, rect.height)
        let k = side / 256
        let origin = CGPoint(x: rect.midX - 128 * k, y: rect.midY - 129 * k)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * k, y: origin.y + y * k) }

        var path = Path()
        path.move(to: p(128, 20))
        path.addLine(to: p(216, 52))
        path.addLine(to: p(216, 120))
        path.addCurve(to: p(128, 238), control1: p(216, 176), control2: p(176, 218))
        path.addCurve(to: p(40, 120), control1: p(80, 218), control2: p(40, 176))
        path.addLine(to: p(40, 52))
        path.closeSubpath()

        path.addRoundedRect(in: CGRect(x: origin.x + 80 * k, y: origin.y + 98 * k, width: 96 * k, height: 48 * k),
                            cornerSize: CGSize(width: 24 * k, height: 24 * k))
        path.addEllipse(in: CGRect(x: origin.x + 137 * k, y: origin.y + 107 * k, width: 30 * k, height: 30 * k))
        return path
    }
}

struct LogoMark: View {
    var size: CGFloat = 56
    var body: some View {
        LogoShape()
            .fill(Theme.accent, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
