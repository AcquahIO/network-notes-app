import SwiftUI

struct ResourceCard: View {
    let resource: ResourceLink

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(resource.title)
                .font(Typography.titleM)
                .foregroundColor(AppColors.textPrimary)
            Text(resource.sourceName)
                .font(Typography.caption)
                .foregroundColor(AppColors.textSecondary)
            Text(resource.description)
                .font(Typography.body)
                .foregroundColor(AppColors.textPrimary)
            HStack {
                Spacer()
                Link("Open", destination: URL(string: resource.url) ?? URL(string: "https://example.com")!)
                    .font(Typography.callout)
                    .foregroundColor(AppColors.accent)
            }
        }
        .padding(Spacing.lg)
        .background(AppTheme.glassBackground())
        .shadow(color: AppColors.shadow, radius: 12, x: 0, y: 8)
    }
}
