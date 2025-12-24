import SwiftUI

struct ShareSheetView: View {
    let sessionId: String
    let sessionTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var scope: String = "summary_transcript"
    @State private var shareLink: String?
    @State private var emailList: String = ""
    @State private var note: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let api = APIClient.shared
    private let scopeOptions: [(label: String, value: String)] = [
        ("Summary only", "summary_only"),
        ("Summary + Transcript", "summary_transcript"),
        ("Everything", "everything")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient().ignoresSafeArea()
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Share \"\(sessionTitle)\"")
                        .font(Typography.titleL)
                        .foregroundColor(AppColors.textPrimary)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Share scope")
                            .font(Typography.callout)
                            .foregroundColor(AppColors.textSecondary)
                        Picker("Scope", selection: $scope) {
                            ForEach(scopeOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Share link")
                            .font(Typography.callout)
                            .foregroundColor(AppColors.textSecondary)
                        if let shareLink {
                            ShareLink(item: shareLink) {
                                Label("Share link", systemImage: "square.and.arrow.up")
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            Text(shareLink)
                                .font(Typography.caption)
                                .foregroundColor(AppColors.textSecondary)
                        } else {
                            Button(action: { Task { await generateLink() } }) {
                                Text(isWorking ? "Generating..." : "Generate link")
                                    .font(Typography.callout)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(AppColors.card, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .foregroundColor(AppColors.textPrimary)
                            .disabled(isWorking)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Email share")
                            .font(Typography.callout)
                            .foregroundColor(AppColors.textSecondary)
                        TextField("Emails (comma separated)", text: $emailList)
                            .padding()
                            .background(AppColors.card, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundColor(AppColors.textPrimary)
                        TextField("Optional note", text: $note)
                            .padding()
                            .background(AppColors.card, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundColor(AppColors.textPrimary)
                        Button(action: { Task { await sendEmail() } }) {
                            Text(isWorking ? "Sending..." : "Send email")
                                .font(Typography.callout)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(AppColors.background)
                        }
                        .disabled(isWorking || parsedEmails().isEmpty)
                    }
                    Spacer()
                }
                .padding(Spacing.xl)
            }
            .navigationTitle("Share")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .alert("Share", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func generateLink() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await api.createShareLink(sessionId: sessionId, scope: scope)
            shareLink = response.shareLink
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendEmail() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.sendShareEmail(sessionId: sessionId, emails: parsedEmails(), message: note, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedEmails() -> [String] {
        emailList
            .split { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
