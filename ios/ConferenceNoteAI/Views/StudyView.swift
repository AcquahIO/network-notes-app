import SwiftUI

struct StudyView: View {
    @ObservedObject var viewModel: StudyViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Study")
                    .font(Typography.titleXL)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)
                if viewModel.isLoading {
                    ProgressView().tint(AppColors.accent)
                }
                ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { index, session in
                    NavigationLink(destination: SessionDetailView(sessionId: session.id)) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(session.title)
                                .font(Typography.titleM)
                                .foregroundColor(AppColors.textPrimary)
                            if let summary = session.summary {
                                Text(summary)
                                    .font(Typography.body)
                                    .foregroundColor(AppColors.textSecondary)
                                    .lineLimit(2)
                            }
                            if let syncState = session.syncState {
                                Text(syncState.label)
                                    .font(Typography.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            HStack(spacing: Spacing.md) {
                                Label("\(session.photoCount ?? 0) photos", systemImage: "camera.fill")
                                Label("\(session.resourceCount ?? 0) resources", systemImage: "link")
                            }
                            .font(Typography.caption)
                            .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(Spacing.lg)
                        .background(AppTheme.glassBackground())
                        .shadow(color: AppColors.shadow, radius: 12, x: 0, y: 8)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.bottom, Spacing.md)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .animation(.easeInOut.delay(Double(index) * 0.07), value: viewModel.sessions.count)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(AppTheme.backgroundGradient().ignoresSafeArea())
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Study", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
