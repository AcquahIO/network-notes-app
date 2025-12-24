import Foundation

actor LocalStore {
    static let shared = LocalStore()

    private let baseURL: URL

    struct StoredSessionDetail: Codable {
        let detail: SessionDetail
        let syncState: SyncState?
        let cachedAt: Date
    }

    struct SyncJob: Codable, Identifiable {
        enum JobType: String, Codable {
            case createSession
            case uploadAudio
            case uploadPhoto
            case sendChat
        }

        let id: String
        var type: JobType
        var sessionId: String
        var title: String?
        var audioFilePath: String?
        var audioDuration: Int?
        var photoFilePath: String?
        var takenAtSeconds: Int?
        var chatMessage: String?
        var chatLanguage: String?
        var includeExternalReading: Bool?
        var attempts: Int
        var createdAt: Date
    }

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        baseURL = base.appendingPathComponent("ConferenceNoteAI/Offline", isDirectory: true)
    }

    private func ensureDirectories() throws {
        let fm = FileManager.default
        let sessionsDir = sessionsDirectory()
        if !fm.fileExists(atPath: sessionsDir.path) {
            try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func sessionsDirectory() -> URL {
        baseURL.appendingPathComponent("sessions", isDirectory: true)
    }

    private func sessionFileURL(sessionId: String) -> URL {
        sessionsDirectory().appendingPathComponent("\(sessionId).json")
    }

    private func queueFileURL() -> URL {
        baseURL.appendingPathComponent("sync_queue.json")
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func updatedDetail(_ stored: StoredSessionDetail) -> SessionDetail {
        var session = stored.detail.session
        session.syncState = stored.syncState
        return SessionDetail(
            session: session,
            audio: stored.detail.audio,
            photos: stored.detail.photos,
            transcript: stored.detail.transcript,
            summary: stored.detail.summary,
            resources: stored.detail.resources,
            chatMessages: stored.detail.chatMessages
        )
    }

    private func copySession(_ session: Session, newId: String) -> Session {
        Session(
            id: newId,
            title: session.title,
            status: session.status,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            photoCount: session.photoCount,
            resourceCount: session.resourceCount,
            summary: session.summary,
            transcriptLanguage: session.transcriptLanguage,
            summaryLanguage: session.summaryLanguage,
            speakerMetadata: session.speakerMetadata,
            topicContext: session.topicContext,
            sharedFromSessionId: session.sharedFromSessionId,
            syncState: session.syncState
        )
    }

    func saveSessionDetail(_ detail: SessionDetail, syncState: SyncState? = nil) async {
        do {
            try ensureDirectories()
            let stored = StoredSessionDetail(detail: detail, syncState: syncState, cachedAt: Date())
            try writeJSON(stored, to: sessionFileURL(sessionId: detail.session.id))
        } catch {
            print("Failed to save session detail: \(error)")
        }
    }

    func loadSessionDetail(sessionId: String) async -> SessionDetail? {
        guard let stored = readJSON(StoredSessionDetail.self, from: sessionFileURL(sessionId: sessionId)) else {
            return nil
        }
        return updatedDetail(stored)
    }

    func listSessions() async -> [Session] {
        do {
            try ensureDirectories()
            let files = try FileManager.default.contentsOfDirectory(at: sessionsDirectory(), includingPropertiesForKeys: nil)
            let sessions = files.compactMap { url -> Session? in
                guard let stored = readJSON(StoredSessionDetail.self, from: url) else { return nil }
                var session = stored.detail.session
                session.syncState = stored.syncState
                return session
            }
            return sessions.sorted { ($0.startedAt ?? Date.distantPast) > ($1.startedAt ?? Date.distantPast) }
        } catch {
            print("Failed to list sessions: \(error)")
            return []
        }
    }

    func updateSyncState(sessionId: String, state: SyncState?) async {
        guard let stored = readJSON(StoredSessionDetail.self, from: sessionFileURL(sessionId: sessionId)) else { return }
        let updated = StoredSessionDetail(detail: stored.detail, syncState: state, cachedAt: stored.cachedAt)
        do {
            try writeJSON(updated, to: sessionFileURL(sessionId: sessionId))
        } catch {
            print("Failed to update sync state: \(error)")
        }
    }

    func renameSessionId(from oldId: String, to newId: String) async {
        let oldURL = sessionFileURL(sessionId: oldId)
        guard let stored = readJSON(StoredSessionDetail.self, from: oldURL) else { return }
        let newSession = copySession(stored.detail.session, newId: newId)
        let updatedDetail = SessionDetail(
            session: newSession,
            audio: stored.detail.audio,
            photos: stored.detail.photos,
            transcript: stored.detail.transcript,
            summary: stored.detail.summary,
            resources: stored.detail.resources,
            chatMessages: stored.detail.chatMessages
        )
        let updated = StoredSessionDetail(detail: updatedDetail, syncState: stored.syncState, cachedAt: stored.cachedAt)
        do {
            try ensureDirectories()
            try writeJSON(updated, to: sessionFileURL(sessionId: newId))
            try FileManager.default.removeItem(at: oldURL)
        } catch {
            print("Failed to rename session: \(error)")
        }
    }

    func loadQueue() async -> [SyncJob] {
        do {
            try ensureDirectories()
            return readJSON([SyncJob].self, from: queueFileURL()) ?? []
        } catch {
            print("Failed to load queue: \(error)")
            return []
        }
    }

    func saveQueue(_ jobs: [SyncJob]) async {
        do {
            try ensureDirectories()
            try writeJSON(jobs, to: queueFileURL())
        } catch {
            print("Failed to save queue: \(error)")
        }
    }
}
