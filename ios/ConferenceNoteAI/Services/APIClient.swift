import Foundation

@MainActor
final class APIClient {
    static let shared = APIClient()
    private init() {}

    private let baseURL = URL(string: "http://localhost:4000")!
    private var isDemo = false
    private var demoStore: [String: SessionDetail] = [:]
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var token: String? {
        KeychainStorage.shared.loadToken(for: "ConferenceNoteAI.jwt")
    }

    func enableDemoMode() { isDemo = true }
    func disableDemoMode() { isDemo = false }

    func setToken(_ token: String) {
        KeychainStorage.shared.save(token: token, for: "ConferenceNoteAI.jwt")
    }

    func clearToken() { KeychainStorage.shared.deleteToken(for: "ConferenceNoteAI.jwt") }

    private func makeRequest<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "APIError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: Auth
    func register(email: String, password: String) async throws -> AuthResponse {
        if isDemo {
            let user = User(id: UUID().uuidString, email: email)
            return AuthResponse(token: "demo-token", user: user)
        }
        return try await makeRequest("/api/auth/register", method: "POST", body: ["email": email, "password": password])
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        if isDemo {
            let user = User(id: UUID().uuidString, email: email)
            return AuthResponse(token: "demo-token", user: user)
        }
        return try await makeRequest("/api/auth/login", method: "POST", body: ["email": email, "password": password])
    }

    // MARK: Sessions
    func fetchSessions() async throws -> [Session] {
        if isDemo { return demoSessions() }
        return try await makeRequest("/api/sessions")
    }

    func createSession(title: String?) async throws -> Session {
        if isDemo {
            let new = makeDemoRecordingSession(title: title ?? "Untitled Session")
            demoStore[new.id] = makeEmptyDemoDetail(from: new)
            return new
        }
        return try await makeRequest("/api/sessions", method: "POST", body: ["title": title ?? "Untitled Session"])
    }

    func fetchSessionDetail(id: String) async throws -> SessionDetail {
        if isDemo {
            if let existing = demoStore[id] { return existing }
            let demo = makeDemoDetail(from: makeDemoSession(id: id, title: "Demo Session"))
            demoStore[id] = demo
            return demo
        }
        return try await makeRequest("/api/sessions/\(id)")
    }

    func resummarizeSession(
        sessionId: String,
        speakerMetadata: SpeakerMetadata?,
        topicContext: String?,
        language: String?
    ) async throws -> Summary {
        if isDemo {
            guard var detail = demoStore[sessionId], let summary = detail.summary else {
                throw NSError(domain: "APIError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Missing summary"])
            }
            let updated = Summary(
                shortSummary: summary.shortSummary,
                detailedSummary: summary.detailedSummary,
                keyPointsJson: summary.keyPointsJson,
                actionItemsJson: summary.actionItemsJson,
                highlightsJson: summary.highlightsJson ?? ["Highlight one", "Highlight two", "Highlight three"],
                language: language ?? summary.language
            )
            detail = SessionDetail(
                session: detail.session,
                audio: detail.audio,
                photos: detail.photos,
                transcript: detail.transcript,
                summary: updated,
                resources: detail.resources,
                chatMessages: detail.chatMessages
            )
            demoStore[sessionId] = detail
            return updated
        }
        struct Response: Decodable { let summary: Summary }
        let speakerPayload: [String: Any]? = speakerMetadata.map { metadata in
            [
                "count": metadata.count ?? metadata.speakers.count,
                "speakers": metadata.speakers.map { ["name": $0.name, "role": $0.role as Any] }
            ]
        }
        var body: [String: Any] = [:]
        if let speakerPayload { body["speaker_metadata"] = speakerPayload }
        if let topicContext { body["topic_context"] = topicContext }
        if let language { body["language"] = language }
        let response: Response = try await makeRequest("/api/sessions/\(sessionId)/resummarize", method: "POST", body: body)
        return response.summary
    }

    func sendChatMessage(
        sessionId: String,
        message: String,
        language: String?,
        includeExternalReading: Bool
    ) async throws -> (String, [Citation], [ExternalLink]) {
        if isDemo {
            return (
                "Demo response from this session.",
                [Citation(chunkId: nil, startTimeSeconds: 0, endTimeSeconds: 10, text: "Demo transcript snippet.")],
                []
            )
        }
        struct Response: Decodable {
            let assistantMessage: String
            let citations: [Citation]
            let externalLinks: [ExternalLink]
        }
        var body: [String: Any] = [
            "message": message,
            "include_external_reading": includeExternalReading
        ]
        if let language { body["language"] = language }
        let response: Response = try await makeRequest(
            "/api/sessions/\(sessionId)/chat",
            method: "POST",
            body: body
        )
        return (response.assistantMessage, response.citations, response.externalLinks)
    }

    func createShareLink(sessionId: String, scope: String) async throws -> ShareLinkResponse {
        if isDemo {
            return ShareLinkResponse(shareToken: UUID().uuidString, shareLink: "conferencenoteai://share?token=demo", scope: scope)
        }
        return try await makeRequest("/api/sessions/\(sessionId)/share", method: "POST", body: ["scope": scope])
    }

    func sendShareEmail(sessionId: String, emails: [String], message: String?, scope: String) async throws -> VoidResponse {
        if isDemo { return VoidResponse(message: "demo-email") }
        var body: [String: Any] = ["emails": emails, "scope": scope]
        if let message, !message.isEmpty { body["message"] = message }
        return try await makeRequest(
            "/api/sessions/\(sessionId)/share/email",
            method: "POST",
            body: body
        )
    }

    func fetchShare(token: String) async throws -> SharePayload {
        if isDemo {
            return SharePayload(
                share: ShareRecord(id: UUID().uuidString, sessionId: UUID().uuidString, shareToken: token, scope: "summary_transcript", createdAt: Date(), expiresAt: nil),
                session: makeDemoSession(title: "Shared Session"),
                summary: demoSummary(),
                transcript: demoTranscriptSegments(),
                resources: demoResources(),
                externalLinks: []
            )
        }
        return try await makeRequest("/api/shares/\(token)")
    }

    func importShare(token: String) async throws -> String {
        if isDemo { return UUID().uuidString }
        struct Response: Decodable { let sessionId: String }
        let response: Response = try await makeRequest("/api/shares/\(token)/import", method: "POST")
        return response.sessionId
    }

    func uploadAudio(sessionId: String, fileUrl: String, duration: Int?) async throws -> VoidResponse {
        if isDemo {
            if var detail = demoStore[sessionId] {
                var session = detail.session
                session.status = .processing
                session.endedAt = Date()
                session.durationSeconds = duration

                let audio = AudioRecording(id: UUID().uuidString, fileUrl: fileUrl, durationSeconds: duration)
                detail = SessionDetail(session: session, audio: audio, photos: detail.photos, transcript: [], summary: nil, resources: detail.resources, chatMessages: detail.chatMessages)
                demoStore[sessionId] = detail
                kickoffDemoProcessing(sessionId: sessionId)
            }
            return VoidResponse(message: "demo-processing")
        }
        var body: [String: Any] = ["durationSeconds": duration ?? 0]
        if let url = URL(string: fileUrl), url.isFileURL {
            let data = try await loadFileData(url: url)
            body["audioBase64"] = data.base64EncodedString()
            body["fileName"] = url.lastPathComponent
            body["mimeType"] = "audio/mp4"
        } else {
            body["fileUrl"] = fileUrl
        }
        return try await makeRequest("/api/sessions/\(sessionId)/audio", method: "POST", body: body)
    }

    func uploadPhoto(sessionId: String, fileUrl: String, takenAtSeconds: Int) async throws -> PhotoAsset {
        if isDemo {
            var photo = PhotoAsset(id: UUID().uuidString, fileUrl: fileUrl, takenAtOffsetSeconds: takenAtSeconds, ocrText: nil, transcriptSegment: nil)
            if let detail = demoStore[sessionId] {
                var updatedPhotos = detail.photos
                updatedPhotos.append(photo)
                updatedPhotos.sort { $0.takenAtOffsetSeconds < $1.takenAtOffsetSeconds }
                let aligned = alignDemoPhotosToSegments(updatedPhotos, segments: detail.transcript)
                if let matched = aligned.first(where: { $0.id == photo.id }) { photo = matched }
                let updatedDetail = SessionDetail(session: detail.session, audio: detail.audio, photos: aligned, transcript: detail.transcript, summary: detail.summary, resources: detail.resources, chatMessages: detail.chatMessages)
                demoStore[sessionId] = updatedDetail
            }
            return photo
        }
        return try await makeRequest("/api/sessions/\(sessionId)/photos", method: "POST", body: ["fileUrl": fileUrl, "takenAtSeconds": takenAtSeconds])
    }

    func fetchStudySessions() async throws -> [Session] {
        if isDemo { return demoSessions().filter { $0.status == .ready } }
        return try await makeRequest("/api/study")
    }

    // MARK: Demo helpers
    private func demoSessions() -> [Session] {
        if demoStore.isEmpty {
            let demo = makeDemoDetail(from: makeDemoSession(title: "Keynote: Future of AI Notes"))
            demoStore[demo.session.id] = demo
        }
        return demoStore.values.map { detail in
            var session = detail.session
            session.photoCount = detail.photos.count
            session.resourceCount = detail.resources.count
            session.summary = detail.summary?.shortSummary
            return session
        }.sorted { ($0.startedAt ?? Date()) > ($1.startedAt ?? Date()) }
    }

    private func makeDemoSession(id: String = UUID().uuidString, title: String) -> Session {
        Session(
            id: id,
            title: title,
            status: .ready,
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            durationSeconds: 1800,
            photoCount: 2,
            resourceCount: 2,
            summary: "AI-assisted note-taking with slides and transcripts.",
            transcriptLanguage: "en",
            summaryLanguage: "en",
            speakerMetadata: nil,
            topicContext: nil,
            sharedFromSessionId: nil,
            syncState: nil
        )
    }

    private func makeDemoRecordingSession(id: String = UUID().uuidString, title: String) -> Session {
        Session(
            id: id,
            title: title,
            status: .recording,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            photoCount: 0,
            resourceCount: 0,
            summary: nil,
            transcriptLanguage: nil,
            summaryLanguage: nil,
            speakerMetadata: nil,
            topicContext: nil,
            sharedFromSessionId: nil,
            syncState: nil
        )
    }

    private func makeDemoDetail(from session: Session) -> SessionDetail {
        let transcript: [TranscriptSegment] = [
            TranscriptSegment(id: UUID().uuidString, startTimeSeconds: 0, endTimeSeconds: 45, text: "Welcome to Conference Note AI, capturing talks effortlessly."),
            TranscriptSegment(id: UUID().uuidString, startTimeSeconds: 45, endTimeSeconds: 90, text: "Align slide photos with transcript for instant context."),
            TranscriptSegment(id: UUID().uuidString, startTimeSeconds: 90, endTimeSeconds: 140, text: "Study hub surfaces TL;DR and resources.")
        ]
        let photos: [PhotoAsset] = transcript.enumerated().map { idx, seg in
            PhotoAsset(
                id: UUID().uuidString,
                fileUrl: "https://picsum.photos/seed/demo\(idx)/400/250",
                takenAtOffsetSeconds: seg.startTimeSeconds + 5,
                ocrText: nil,
                transcriptSegment: seg
            )
        }
        let summary = Summary(
            shortSummary: "Captured audio, aligned slides, and AI summary ready for study.",
            detailedSummary: "A walkthrough of recording, aligning slide captures, and surfacing concise takeaways.",
            keyPointsJson: [
                "Record audio while snapping slide photos.",
                "Slides align with transcript segments automatically.",
                "Study view delivers TL;DR and resources."
            ],
            actionItemsJson: [
                "Try capturing in noisy rooms.",
                "Export notes to your favorite tools."
            ],
            highlightsJson: [
                "Audio and slides stay in sync.",
                "Transcript alignment accelerates review.",
                "Study-ready takeaways reduce rewatch time."
            ],
            language: "en"
        )
        let resources = [
            ResourceLink(id: UUID().uuidString, title: "Designing capture flows", url: "https://example.com/capture", sourceName: "Product Patterns", description: "Low-friction capture patterns."),
            ResourceLink(id: UUID().uuidString, title: "iOS audio recording tips", url: "https://example.com/audio", sourceName: "iOS Audio Guide", description: "Best practices for AVAudioSession.")
        ]
        let audio = AudioRecording(id: UUID().uuidString, fileUrl: "https://example.com/audio.m4a", durationSeconds: session.durationSeconds)
        return SessionDetail(session: session, audio: audio, photos: photos, transcript: transcript, summary: summary, resources: resources, chatMessages: [])
    }

    private func loadFileData(url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
    }

    private func makeEmptyDemoDetail(from session: Session) -> SessionDetail {
        SessionDetail(session: session, audio: nil, photos: [], transcript: [], summary: nil, resources: [], chatMessages: [])
    }

    private func kickoffDemoProcessing(sessionId: String) {
        Task {
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            completeDemoProcessing(sessionId: sessionId)
        }
    }

    private func completeDemoProcessing(sessionId: String) {
        guard var detail = demoStore[sessionId] else { return }

        let transcript = demoTranscriptSegments()
        let summary = demoSummary()
        let resources = demoResources()
        let alignedPhotos = alignDemoPhotosToSegments(detail.photos, segments: transcript)

        var session = detail.session
        session.status = .ready

        detail = SessionDetail(session: session, audio: detail.audio, photos: alignedPhotos, transcript: transcript, summary: summary, resources: resources, chatMessages: detail.chatMessages)
        demoStore[sessionId] = detail
    }

    private func alignDemoPhotosToSegments(_ photos: [PhotoAsset], segments: [TranscriptSegment]) -> [PhotoAsset] {
        guard !segments.isEmpty else { return photos }
        return photos.map { photo in
            var updated = photo
            updated.transcriptSegment = segments.first(where: {
                photo.takenAtOffsetSeconds >= $0.startTimeSeconds && photo.takenAtOffsetSeconds < $0.endTimeSeconds
            })
            return updated
        }
    }

    private func demoTranscriptSegments() -> [TranscriptSegment] {
        let base = [
            "Welcome to Conference Note AI, where we help you capture talks effortlessly.",
            "We align slide photos to the transcript so you can revisit moments quickly.",
            "Our study hub surfaces key takeaways and related resources.",
            "Future versions will ship real AI summaries and smart resource discovery."
        ]
        return base.enumerated().map { idx, text in
            TranscriptSegment(id: UUID().uuidString, startTimeSeconds: idx * 45, endTimeSeconds: idx * 45 + 40, text: text)
        }
    }

    private func demoSummary() -> Summary {
        let tldr = "Speaker outlined a practical path for AI-assisted note taking and study workflows, focusing on capturing audio and slide context with minimal friction."
        return Summary(
            shortSummary: tldr,
            detailedSummary: "\(tldr) The talk emphasized aligning photos to transcript timestamps and delivering concise study-ready outputs.",
            keyPointsJson: [
                "Capture audio and slides together to preserve context.",
                "Auto-transcribe and align images to transcript segments.",
                "Provide TL;DR, takeaways, and study resources quickly."
            ],
            actionItemsJson: [
                "Test the recording workflow in noisy environments.",
                "Prototype AI alignment on a larger sample.",
                "Ship resource recommendations backed by search."
            ],
            highlightsJson: [
                "Capture audio + slides for context.",
                "Alignment simplifies review.",
                "Study resources accelerate recall."
            ],
            language: "en"
        )
    }

    private func demoResources() -> [ResourceLink] {
        [
            ResourceLink(
                id: UUID().uuidString,
                title: "Designing delightful capture flows",
                url: "https://example.com/designing-capture-flows",
                sourceName: "Product Patterns",
                description: "Patterns for low-friction capture with progressive disclosure."
            ),
            ResourceLink(
                id: UUID().uuidString,
                title: "Building robust audio recorders on iOS",
                url: "https://example.com/ios-audio-recording",
                sourceName: "iOS Audio Guide",
                description: "Best practices for AVAudioSession, background modes, and interruptions."
            )
        ]
    }
}

struct VoidResponse: Decodable { let message: String? }
