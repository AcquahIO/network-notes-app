import SwiftUI

struct SessionListView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @Binding var showRecorder: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if viewModel.isLoading {
                    ProgressView().tint(AppColors.accent)
                }
                ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { index, session in
                    NavigationLink(destination: SessionDetailView(sessionId: session.id)) {
                        SessionCardView(session: session)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .animation(.easeOut.delay(Double(index) * 0.05), value: viewModel.sessions.count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.xl)
        }
        .background(AppTheme.backgroundGradient().ignoresSafeArea())
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Sessions", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("My Sessions")
                    .font(Typography.titleXL)
                    .foregroundColor(AppColors.textPrimary)
                Text("Review recordings, slides, and AI notes.")
                    .font(Typography.body)
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
            Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showRecorder = true } }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .padding(Spacing.sm)
                    .background(AppColors.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
