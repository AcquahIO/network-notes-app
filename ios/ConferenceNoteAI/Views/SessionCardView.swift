import SwiftUI

struct SessionCardView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(session.title)
                    .font(Typography.titleM)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                StatusBadge(status: session.status)
            }
            if let syncState = session.syncState {
                Text(syncState.label)
                    .font(Typography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            HStack(spacing: Spacing.md) {
                Label(session.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--", systemImage: "calendar")
                Label(session.displayDuration, systemImage: "clock")
            }
            .font(Typography.caption)
            .foregroundColor(AppColors.textSecondary)
        }
        .padding(Spacing.lg)
        .background(AppTheme.glassBackground())
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(color: AppColors.shadow, radius: 14, x: 0, y: 10)
    }
}

struct StatusBadge: View {
    let status: SessionStatus
    var body: some View {
        let text: String
        let color: Color
        switch status {
        case .recording: text = "Recording"; color = .orange
        case .processing: text = "Processing"; color = .yellow
        case .ready: text = "Ready"; color = .green
        case .failed: text = "Failed"; color = AppColors.destructive
        }
        return Text(text)
            .font(Typography.caption)
            .foregroundColor(AppColors.background)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(color.opacity(0.9), in: Capsule())
    }
}
