import SwiftUI
import UIKit

/// Kolory semantyczne aplikacji i widgetów.
///
/// W ciemnym wyglądzie to kolory systemowe (kontrast na czerni 5–12:1). W jasnym wyglądzie systemowe odcienie
/// (np. pomarańczowy #FF9500, cyjan #00C0E8) mają na jasnym tle tylko 1,8–3:1, więc używamy ciemniejszych wariantów
/// o kontraście co najmniej 4,7:1 na tle kafelków i kart (WCAG AA dla tekstu do 17 pt: 4,5:1).
enum Palette {
    private static func adaptive(light: UInt32, dark: UIColor) -> Color {
        let lightColor = UIColor(red: CGFloat((light >> 16) & 0xFF) / 255,
                                 green: CGFloat((light >> 8) & 0xFF) / 255,
                                 blue: CGFloat(light & 0xFF) / 255, alpha: 1)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : lightColor })
    }

    static let accent = adaptive(light: 0x006E85, dark: .systemCyan)
    static let red = adaptive(light: 0xCC0B00, dark: .systemRed)
    static let green = adaptive(light: 0x1E7434, dark: .systemGreen)
    static let orange = adaptive(light: 0x945600, dark: .systemOrange)
    static let blue = adaptive(light: 0x0062CC, dark: .systemBlue)
    static let purple = adaptive(light: 0x9B29D4, dark: .systemPurple)
    /// Tekst na wypełnieniu kolorem akcentu: biały w jasnym, czarny w ciemnym motywie (kontrast ≥ 4,5:1).
    static let onAccent = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
}

