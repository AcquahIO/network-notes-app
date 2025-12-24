import SwiftUI

struct ImportSessionView: View {
    let token: String
    @Environment(\.dismiss) private var dismiss
    @State private var payload: SharePayload?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    private let api = APIClient.shared
    private let store = LocalStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient().ignoresSafeArea()
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if isLoading {
                        ProgressView().tint(AppColors.accent)
                    } else if let payload {
                        Text(payload.session.title)
                            .font(Typography.titleL)
                            .foregroundColor(AppColors.textPrimary)

                        if let summary = payload.summary {
                            Text("Summary")
                                .font(Typography.callout)
                                .foregroundColor(AppColors.textSecondary)
                            Text(summary.shortSummary)
                                .font(Typography.body)
                                .foregroundColor(AppColors.textPrimary)
                        }

                        if let highlights = payload.summary?.highlightsJson, !highlights.isEmpty {
                            Text("3 Key Highlights")
                                .font(Typography.callout)
                                .foregroundColor(AppColors.textSecondary)
                            ForEach(highlights, id: \.self) { highlight in
                                Label(highlight, systemImage: "sparkles")
                                    .foregroundColor(AppColors.textPrimary)
                            }
                        }

                        if payload.transcript.isEmpty {
                            Text("Transcript not included in this share.")
                                .font(Typography.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Button(action: { Task { await importShare() } }) {
                            Text(isImporting ? "Importing..." : "Save to my library")
                                .font(Typography.callout)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(AppColors.accent, in: Capsule())
                                .foregroundColor(AppColors.background)
                        }
                        .disabled(isImporting)
                    } else {
                        Text("Unable to load shared session.")
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(Spacing.xl)
            }
            .navigationTitle("Import Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .task { await loadShare() }
        .alert("Import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadShare() async {
        isLoading = true
        defer { isLoading = false }
        do {
            payload = try await api.fetchShare(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importShare() async {
        guard payload != nil else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let sessionId = try await api.importShare(token: token)
            let detail = try await api.fetchSessionDetail(id: sessionId)
            await store.saveSessionDetail(detail, syncState: detail.session.syncState)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
