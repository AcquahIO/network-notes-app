import SwiftUI

struct ChatPanelView: View {
    let messages: [ChatMessage]
    @Binding var input: String
    let isSending: Bool
    @Binding var includeExternalReading: Bool
    let isOnline: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Session Chat")
                .font(Typography.titleM)
                .foregroundColor(AppColors.textPrimary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(messages) { message in
                        ChatMessageBubble(message: message)
                    }
                }
            }
            .frame(minHeight: 220, maxHeight: 360)

            Toggle("Include further reading", isOn: $includeExternalReading)
                .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))
                .font(Typography.caption)

            HStack(spacing: Spacing.sm) {
                TextField("Ask about this session...", text: $input, axis: .vertical)
                    .padding(Spacing.md)
                    .background(AppColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(AppColors.textPrimary)
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(AppColors.background)
                        .padding(Spacing.md)
                        .background(AppColors.accent, in: Circle())
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }

            if !isOnline {
                Text("Offline: messages will send when back online.")
                    .font(Typography.caption)
                    .foregroundColor(AppColors.textSecondary)
                if includeExternalReading {
                    Text("Further reading is unavailable while offline.")
                        .font(Typography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .padding(Spacing.lg)
        .background(AppTheme.glassBackground())
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.sm) {
            Text(message.content)
                .font(Typography.body)
                .foregroundColor(AppColors.textPrimary)
                .padding(Spacing.md)
                .background(
                    message.role == .user
                        ? AppColors.accent.opacity(0.2)
                        : AppColors.card
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let status = message.status, status != .sent {
                Text(statusLabel(status))
                    .font(Typography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            if message.role == .assistant, let citations = message.citations, !citations.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("From this session")
                        .font(Typography.caption)
                        .foregroundColor(AppColors.textSecondary)
                    ForEach(citations) { citation in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            if let start = citation.startTimeSeconds {
                                Text("\(start)s")
                                    .font(Typography.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            Text(citation.text)
                                .font(Typography.caption)
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .padding(Spacing.sm)
                        .background(AppColors.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            if message.role == .assistant, let links = message.externalLinks, !links.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Further reading")
                        .font(Typography.caption)
                        .foregroundColor(AppColors.textSecondary)
                    ForEach(links) { link in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            if let title = link.title {
                                Text(title)
                                    .font(Typography.caption)
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            if let url = URL(string: link.url) {
                                Link(link.url, destination: url)
                                    .font(Typography.caption)
                                    .foregroundColor(AppColors.accent)
                            } else {
                                Text(link.url)
                                    .font(Typography.caption)
                                    .foregroundColor(AppColors.accent)
                            }
                            if let note = link.note {
                                Text(note)
                                    .font(Typography.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .padding(Spacing.sm)
                        .background(AppColors.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func statusLabel(_ status: ChatMessageStatus) -> String {
        switch status {
        case .queued: return "Queued"
        case .sending: return "Sending"
        case .failed: return "Failed"
        case .sent: return "Sent"
        }
    }
}
