import SwiftUI

struct SessionDetailView: View {
    let sessionId: String
    @StateObject private var viewModel = SessionDetailViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showShareSheet = false
    @State private var showContextSheet = false

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient().ignoresSafeArea()
            if let detail = viewModel.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        header(detail.session)
                        summary(detail.summary)
                        highlights(detail.summary)
                        transcript(detail.transcript, photos: detail.photos)
                        resources(detail.resources)
                        if detail.summary != nil && !detail.transcript.isEmpty {
                            ChatPanelView(
                                messages: viewModel.chatMessages,
                                input: $viewModel.chatInput,
                                isSending: viewModel.isChatSending,
                                includeExternalReading: $viewModel.includeExternalReading,
                                isOnline: networkMonitor.isOnline,
                                onSend: { Task { await viewModel.sendChat() } }
                            )
                        }
                    }
                    .padding(Spacing.xl)
                }
                .refreshable { await viewModel.load(sessionId: sessionId) }
            } else if viewModel.isLoading {
                ProgressView().tint(AppColors.accent)
            } else {
                Text("No data yet").foregroundColor(AppColors.textSecondary)
            }
        }
        .task { await viewModel.load(sessionId: sessionId) }
        .sheet(item: $viewModel.selectedPhoto) { photo in
            PhotoFullscreenView(photo: photo)
        }
        .sheet(isPresented: $showShareSheet) {
            if let detail = viewModel.detail {
                ShareSheetView(sessionId: detail.session.id, sessionTitle: detail.session.title)
            }
        }
        .sheet(isPresented: $showContextSheet) {
            SessionContextSheet(
                speakers: $viewModel.contextSpeakers,
                topicContext: $viewModel.topicContext,
                preferredLanguage: $viewModel.preferredLanguage,
                onSave: { Task { await viewModel.regenerateSummary() } },
                isSaving: viewModel.isLoading
            )
        }
        .alert("Session", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func header(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(session.title)
                        .font(Typography.titleXL)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Duration \(session.displayDuration)")
                        .font(Typography.body)
                        .foregroundColor(AppColors.textSecondary)
                    if let syncState = session.syncState {
                        Text(syncState.label)
                            .font(Typography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                Spacer()
                StatusBadge(status: session.status)
            }
            HStack(spacing: Spacing.md) {
                Button(action: { showShareSheet = true }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(AppColors.card, in: Capsule())
                }
                Button(action: { showContextSheet = true }) {
                    Label("Improve summary", systemImage: "sparkles")
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(AppColors.card, in: Capsule())
                }
                if session.syncState == .error {
                    Button(action: { Task { await SyncManager.shared.processQueue() } }) {
                        Label("Retry sync", systemImage: "arrow.clockwise")
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(AppColors.card, in: Capsule())
                    }
                }
            }
            .font(Typography.caption)
            .foregroundColor(AppColors.textPrimary)
        }
    }

    private func summary(_ summary: Summary?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Summary")
                    .font(Typography.titleM)
                Spacer()
            }
            .foregroundColor(AppColors.textPrimary)
            if let summary {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("TL;DR")
                        .font(Typography.callout)
                        .foregroundColor(AppColors.textSecondary)
                    Text(summary.shortSummary)
                        .font(Typography.body)
                        .foregroundColor(AppColors.textPrimary)
                    Divider().background(AppColors.border)
                    Text("Key Takeaways")
                        .font(Typography.callout)
                        .foregroundColor(AppColors.textSecondary)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(summary.keyPointsJson, id: \.self) { point in
                            Label(point, systemImage: "sparkles")
                                .font(Typography.body)
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }
                }
                .padding(Spacing.lg)
                .background(AppTheme.glassBackground())
            } else {
                ProcessingStateView()
            }
        }
    }

    private func highlights(_ summary: Summary?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("3 Key Highlights")
                .font(Typography.titleM)
                .foregroundColor(AppColors.textPrimary)
            if let highlights = summary?.highlightsJson, !highlights.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(highlights, id: \.self) { highlight in
                        Label(highlight, systemImage: "star.fill")
                            .font(Typography.body)
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
                .padding(Spacing.lg)
                .background(AppTheme.glassBackground())
            } else if summary != nil {
                Text("Highlights are not available yet.")
                    .font(Typography.caption)
                    .foregroundColor(AppColors.textSecondary)
            } else {
                ProcessingStateView()
            }
        }
    }

    private func transcript(_ segments: [TranscriptSegment], photos: [PhotoAsset]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Transcript")
                .font(Typography.titleM)
                .foregroundColor(AppColors.textPrimary)
            if segments.isEmpty {
                ProcessingStateView()
            } else {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(segments) { segment in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("\(segment.startTimeSeconds)s")
                                .font(Typography.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text(segment.text)
                                .font(Typography.body)
                                .foregroundColor(AppColors.textPrimary)
                            let related = photos.filter { $0.transcriptSegment?.id == segment.id }
                            if !related.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: Spacing.md) {
                                        ForEach(related) { photo in
                                            PhotoAssetImageView(fileUrl: photo.fileUrl, scaling: .fill)
                                            .frame(width: 120, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .onTapGesture {
                                                withAnimation(.spring()) { viewModel.selectedPhoto = photo }
                                            }
                                            .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(Spacing.lg)
                        .background(AppTheme.glassBackground())
                    }
                }
            }
        }
    }

    private func resources(_ resources: [ResourceLink]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Study")
                .font(Typography.titleM)
                .foregroundColor(AppColors.textPrimary)
            ForEach(resources) { resource in
                ResourceCard(resource: resource)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

struct ProcessingStateView: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            ProgressView().tint(AppColors.accent)
            VStack(alignment: .leading) {
                Text("Processing your notes…")
                    .foregroundColor(AppColors.textPrimary)
                Text("Transcribing audio, aligning photos, generating summary")
                    .foregroundColor(AppColors.textSecondary)
                    .font(Typography.caption)
            }
        }
        .padding(Spacing.lg)
        .background(AppTheme.glassBackground())
    }
}
