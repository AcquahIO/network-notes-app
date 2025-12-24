import Foundation

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published private(set) var isSyncing = false

    private let api = APIClient.shared
    private let store = LocalStore.shared
    private let network = NetworkMonitor.shared

    private init() {}

    func enqueue(_ job: LocalStore.SyncJob) async {
        var jobs = await store.loadQueue()
        jobs.append(job)
        await store.saveQueue(jobs)
    }

    func processQueue() async {
        guard network.isOnline else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var jobs = await store.loadQueue()
        var completedIds: Set<String> = []

        for index in jobs.indices {
            guard network.isOnline else { break }
            var job = jobs[index]
            if completedIds.contains(job.id) { continue }

            do {
                switch job.type {
                case .createSession:
                    guard let title = job.title else { throw NSError(domain: "Sync", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing title"]) }
                    let session = try await api.createSession(title: title)
                    await store.renameSessionId(from: job.sessionId, to: session.id)
                    jobs = jobs.map { existing in
                        var updated = existing
                        if updated.sessionId == job.sessionId {
                            updated.sessionId = session.id
                        }
                        return updated
                    }
                    notify(sessionId: session.id)
                    completedIds.insert(job.id)
                case .uploadAudio:
                    guard let path = job.audioFilePath else { throw NSError(domain: "Sync", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing audio file"]) }
                    _ = try await api.uploadAudio(sessionId: job.sessionId, fileUrl: path, duration: job.audioDuration)
                    await store.updateSyncState(sessionId: job.sessionId, state: .uploadedPendingTranscription)
                    notify(sessionId: job.sessionId)
                    completedIds.insert(job.id)
                case .uploadPhoto:
                    guard let path = job.photoFilePath else { throw NSError(domain: "Sync", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing photo file"]) }
                    let takenAt = job.takenAtSeconds ?? 0
                    _ = try await api.uploadPhoto(sessionId: job.sessionId, fileUrl: path, takenAtSeconds: takenAt)
                    notify(sessionId: job.sessionId)
                    completedIds.insert(job.id)
                case .sendChat:
                    guard let text = job.chatMessage else { throw NSError(domain: "Sync", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing chat message"]) }
                    let response = try await api.sendChatMessage(
                        sessionId: job.sessionId,
                        message: text,
                        language: job.chatLanguage,
                        includeExternalReading: job.includeExternalReading ?? false
                    )
                    await appendAssistantMessage(
                        sessionId: job.sessionId,
                        originalMessage: text,
                        content: response.0,
                        citations: response.1,
                        externalLinks: response.2,
                        language: job.chatLanguage
                    )
                    completedIds.insert(job.id)
                }
            } catch {
                job.attempts += 1
                jobs[index] = job
                await store.updateSyncState(sessionId: job.sessionId, state: .error)
                notify(sessionId: job.sessionId)
            }
        }

        jobs.removeAll { completedIds.contains($0.id) }
        await store.saveQueue(jobs)
    }

    private func appendAssistantMessage(
        sessionId: String,
        originalMessage: String,
        content: String,
        citations: [Citation],
        externalLinks: [ExternalLink],
        language: String?
    ) async {
        guard let detail = await store.loadSessionDetail(sessionId: sessionId) else { return }
        var updatedMessages = detail.chatMessages
        if let idx = updatedMessages.lastIndex(where: { $0.role == .user && $0.status == .queued && $0.content == originalMessage }) {
            updatedMessages[idx].status = .sent
        }
        let assistant = ChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: content,
            citations: citations,
            externalLinks: externalLinks,
            language: language,
            createdAt: Date(),
            status: .sent
        )
        updatedMessages.append(assistant)
        let updatedDetail = SessionDetail(
            session: detail.session,
            audio: detail.audio,
            photos: detail.photos,
            transcript: detail.transcript,
            summary: detail.summary,
            resources: detail.resources,
            chatMessages: updatedMessages
        )
        await store.saveSessionDetail(updatedDetail, syncState: detail.session.syncState)
        notify(sessionId: sessionId)
    }

    private func notify(sessionId: String) {
        NotificationCenter.default.post(name: .syncDidUpdate, object: sessionId)
    }
}
