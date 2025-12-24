import SwiftUI

struct AppTheme {
    static func backgroundGradient() -> LinearGradient {
        LinearGradient(colors: [AppColors.background, Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
    }

    static var cardCornerRadius: CGFloat { 18 }
    static var shadow: some View { Color.clear.shadow(color: AppColors.shadow, radius: 12, x: 0, y: 10) }

    static func glassBackground() -> some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(AppColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .shadow(color: AppColors.shadow, radius: 18, x: 0, y: 12)
    }
}
