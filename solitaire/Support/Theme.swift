//
//  Theme.swift
//  solitaire
//
//  Visual styling for table themes and shared UI colors.
//

import SwiftUI

extension TableTheme {
    var feltCenter: Color {
        switch self {
        case .forest: return Color(red: 0.145, green: 0.485, blue: 0.305)
        case .midnight: return Color(red: 0.180, green: 0.210, blue: 0.330)
        case .ocean: return Color(red: 0.100, green: 0.400, blue: 0.480)
        case .wine: return Color(red: 0.450, green: 0.145, blue: 0.205)
        }
    }

    var feltEdge: Color {
        switch self {
        case .forest: return Color(red: 0.035, green: 0.220, blue: 0.130)
        case .midnight: return Color(red: 0.045, green: 0.055, blue: 0.115)
        case .ocean: return Color(red: 0.025, green: 0.155, blue: 0.220)
        case .wine: return Color(red: 0.190, green: 0.045, blue: 0.085)
        }
    }

    /// Tint used for prominent buttons over this felt.
    var accent: Color {
        switch self {
        case .forest: return Color(red: 1.00, green: 0.83, blue: 0.35)
        case .midnight: return Color(red: 0.55, green: 0.72, blue: 1.00)
        case .ocean: return Color(red: 0.55, green: 0.95, blue: 0.90)
        case .wine: return Color(red: 1.00, green: 0.78, blue: 0.55)
        }
    }
}

/// Full-bleed felt table background with a soft vignette and subtle texture.
struct TableBackground: View {
    var theme: TableTheme

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [theme.feltCenter, theme.feltEdge],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 0,
                endRadius: 900
            )
            // Subtle woven texture.
            Canvas { context, size in
                context.opacity = 0.028
                var y: CGFloat = 0
                while y < size.height {
                    let line = Path(CGRect(x: 0, y: y, width: size.width, height: 1))
                    context.fill(line, with: .color(.white))
                    y += 4
                }
            }
            .blendMode(.overlay)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

enum UIStyle {
    static let hudText = Color.white.opacity(0.92)
    static let hudSecondary = Color.white.opacity(0.55)
    static let placeholderStroke = Color.white.opacity(0.28)
    static let placeholderFill = Color.black.opacity(0.10)
}
