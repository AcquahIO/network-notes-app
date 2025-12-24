import Foundation

@MainActor
final class SessionDetailViewModel: ObservableObject {
    @Published var detail: SessionDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPhoto: PhotoAsset?
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatInput: String = ""
    @Published var isChatSending = false
    @Published var includeExternalReading = false
    @Published var contextSpeakers: [SpeakerInfo] = []
    @Published var topicContext: String = ""
    @Published var preferredLanguage: String = Locale.current.language.languageCode?.identifier ?? "en"

    private let api = APIClient.shared
    private let store = LocalStore.shared
    private let syncManager = SyncManager.shared
    private let network = NetworkMonitor.shared
    private var pollingTask: Task<Void, Never>?
    private var syncObserver: NSObjectProtocol?

    init() {
        syncObserver = NotificationCenter.default.addObserver(forName: .syncDidUpdate, object: nil, queue: .main) { [weak self] notification in
            guard let sessionId = notification.object as? String else { return }
            Task { await self?.reloadFromStore(sessionId: sessionId) }
        }
    }

    deinit {
        pollingTask?.cancel()
        if let syncObserver {
            NotificationCenter.default.removeObserver(syncObserver)
        }
    }

    func load(sessionId: String) async {
        pollingTask?.cancel()
        isLoading = true
        defer { isLoading = false }
        do {
            if network.isOnline {
                var fetched = try await api.fetchSessionDetail(id: sessionId)
                if let stored = await store.loadSessionDetail(sessionId: sessionId) {
                    let session = mergeSyncState(session: fetched.session, detail: fetched, storedState: stored.session.syncState)
                    fetched = SessionDetail(
                        session: session,
                        audio: fetched.audio,
                        photos: fetched.photos,
                        transcript: fetched.transcript,
                        summary: fetched.summary,
                        resources: fetched.resources,
                        chatMessages: fetched.chatMessages
                    )
                }
                detail = fetched
                await store.saveSessionDetail(fetched, syncState: fetched.session.syncState)
            } else {
                detail = await store.loadSessionDetail(sessionId: sessionId)
            }
            chatMessages = detail?.chatMessages ?? []
            hydrateContext()
            startPollingIfNeeded(sessionId: sessionId)
        } catch {
            errorMessage = error.localizedDescription
            if detail == nil {
                detail = await store.loadSessionDetail(sessionId: sessionId)
                chatMessages = detail?.chatMessages ?? []
                hydrateContext()
            }
        }
    }

    private func startPollingIfNeeded(sessionId: String) {
        guard let detail else { return }
        guard detail.session.status != .ready && detail.session.status != .failed else { return }
        guard network.isOnline else { return }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                do {
                    var latest = try await self.api.fetchSessionDetail(id: sessionId)
                    if let stored = await self.store.loadSessionDetail(sessionId: sessionId) {
                        let session = self.mergeSyncState(session: latest.session, detail: latest, storedState: stored.session.syncState)
                        latest = SessionDetail(
                            session: session,
                            audio: latest.audio,
                            photos: latest.photos,
                            transcript: latest.transcript,
                            summary: latest.summary,
                            resources: latest.resources,
                            chatMessages: latest.chatMessages
                        )
                    }
                    self.detail = latest
                    self.chatMessages = latest.chatMessages
                    await self.store.saveSessionDetail(latest, syncState: latest.session.syncState)
                    if latest.session.status == .ready || latest.session.status == .failed {
                        return
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                    return
                }
            }
        }
    }

    func sendChat() async {
        let trimmed = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let detail else { return }
        chatInput = ""
        let language = preferredLanguage.isEmpty ? nil : preferredLanguage
        let userMessageId = UUID().uuidString
        let userMessage = ChatMessage(
            id: userMessageId,
            role: .user,
            content: trimmed,
            citations: nil,
            externalLinks: nil,
            language: language,
            createdAt: Date(),
            status: network.isOnline ? .sending : .queued
        )
        chatMessages.append(userMessage)
        await persistChatMessages()

        if !network.isOnline {
            let job = LocalStore.SyncJob(
                id: UUID().uuidString,
                type: .sendChat,
                sessionId: detail.session.id,
                title: nil,
                audioFilePath: nil,
                audioDuration: nil,
                photoFilePath: nil,
                takenAtSeconds: nil,
                chatMessage: trimmed,
                chatLanguage: language,
                includeExternalReading: includeExternalReading,
                attempts: 0,
                createdAt: Date()
            )
            await syncManager.enqueue(job)
            return
        }

        isChatSending = true
        defer { isChatSending = false }
        do {
            let response = try await api.sendChatMessage(
                sessionId: detail.session.id,
                message: trimmed,
                language: language,
                includeExternalReading: includeExternalReading
            )
            let assistant = ChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: response.0,
                citations: response.1,
                externalLinks: response.2,
                language: language,
                createdAt: Date(),
                status: .sent
            )
            if let idx = chatMessages.firstIndex(where: { $0.id == userMessageId }) {
                chatMessages[idx].status = .sent
            }
            chatMessages.append(assistant)
            await persistChatMessages()
        } catch {
            errorMessage = error.localizedDescription
            if let idx = chatMessages.firstIndex(where: { $0.id == userMessageId }) {
                chatMessages[idx].status = .failed
                await persistChatMessages()
            }
        }
    }

    func regenerateSummary() async {
        guard let detail else { return }
        guard network.isOnline else {
            errorMessage = "Offline. Connect to the internet to regenerate the summary."
            return
        }
        isLoading = true
        defer { isLoading = false }
        let metadata = SpeakerMetadata(count: contextSpeakers.count, speakers: contextSpeakers)
        let language = preferredLanguage.isEmpty ? nil : preferredLanguage
        do {
            let summary = try await api.resummarizeSession(
                sessionId: detail.session.id,
                speakerMetadata: metadata,
                topicContext: topicContext,
                language: language
            )
            var session = detail.session
            session.speakerMetadata = metadata
            session.topicContext = topicContext
            session.summaryLanguage = language
            let updated = SessionDetail(
                session: session,
                audio: detail.audio,
                photos: detail.photos,
                transcript: detail.transcript,
                summary: summary,
                resources: detail.resources,
                chatMessages: chatMessages
            )
            self.detail = updated
            await store.saveSessionDetail(updated, syncState: detail.session.syncState)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hydrateContext() {
        guard let detail else { return }
        contextSpeakers = detail.session.speakerMetadata?.speakers ?? []
        topicContext = detail.session.topicContext ?? ""
        preferredLanguage = detail.session.summaryLanguage ?? detail.summary?.language ?? preferredLanguage
    }

    private func persistChatMessages() async {
        guard let detail else { return }
        let updated = SessionDetail(
            session: detail.session,
            audio: detail.audio,
            photos: detail.photos,
            transcript: detail.transcript,
            summary: detail.summary,
            resources: detail.resources,
            chatMessages: chatMessages
        )
        self.detail = updated
        await store.saveSessionDetail(updated, syncState: detail.session.syncState)
    }

    private func reloadFromStore(sessionId: String) async {
        guard detail?.session.id == sessionId else { return }
        if let stored = await store.loadSessionDetail(sessionId: sessionId) {
            detail = stored
            chatMessages = stored.chatMessages
            hydrateContext()
        }
    }

    private func mergeSyncState(session: Session, detail: SessionDetail, storedState: SyncState?) -> Session {
        var updated = session
        updated.syncState = storedState
        if session.status == .ready {
            updated.syncState = .ready
        } else if session.status == .failed {
            updated.syncState = .error
        } else if !detail.transcript.isEmpty && detail.summary == nil {
            updated.syncState = .transcribedPendingSummary
        } else if detail.audio != nil && detail.transcript.isEmpty {
            updated.syncState = .uploadedPendingTranscription
        }
        return updated
    }
}
