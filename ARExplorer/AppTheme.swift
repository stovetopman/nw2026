import SwiftUI

enum AppTheme {
    static let accentBlue = Color(red: 0.18, green: 0.34, blue: 0.98)
    static let accentPink = Color(red: 0.98, green: 0.29, blue: 0.66)
    static let accentYellow = Color(red: 0.99, green: 0.82, blue: 0.23)
    static let ink = Color(red: 0.13, green: 0.13, blue: 0.15)
    static let softInk = Color(red: 0.28, green: 0.28, blue: 0.32)

    static func displayFont(size: CGFloat) -> Font {
        .custom("AvenirNext-Heavy", size: size)
    }

    static func titleFont(size: CGFloat) -> Font {
        .custom("AvenirNext-Bold", size: size)
    }

    static func bodyFont(size: CGFloat) -> Font {
        .custom("AvenirNext-Regular", size: size)
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.99),
                    Color(red: 0.99, green: 0.97, blue: 0.94),
                    Color(red: 0.96, green: 0.98, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.accentPink.opacity(0.08))
                .frame(width: 240, height: 240)
                .offset(x: -140, y: -220)

            Circle()
                .fill(AppTheme.accentBlue.opacity(0.08))
                .frame(width: 260, height: 260)
                .offset(x: 160, y: -140)

            Circle()
                .fill(AppTheme.accentYellow.opacity(0.08))
                .frame(width: 220, height: 220)
                .offset(x: 140, y: 260)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appCard(cornerRadius: CGFloat = 24, stroke: Color = AppTheme.ink, lineWidth: CGFloat = 2) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke, lineWidth: lineWidth)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
    }
}
