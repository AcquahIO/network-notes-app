import Foundation

enum SessionStatus: String, Codable { case recording, processing, ready, failed }

enum SyncState: String, Codable {
    case recordedPendingUpload
    case uploadedPendingTranscription
    case transcribedPendingSummary
    case ready
    case error

    var label: String {
        switch self {
        case .recordedPendingUpload: return "Recorded (pending upload)"
        case .uploadedPendingTranscription: return "Uploaded (pending transcription)"
        case .transcribedPendingSummary: return "Transcribed (pending summary)"
        case .ready: return "Ready"
        case .error: return "Error (tap to retry)"
        }
    }
}

struct Session: Identifiable, Codable {
    let id: String
    var title: String
    var status: SessionStatus
    var startedAt: Date?
    var endedAt: Date?
    var durationSeconds: Int?
    var photoCount: Int?
    var resourceCount: Int?
    var summary: String?
    var transcriptLanguage: String?
    var summaryLanguage: String?
    var speakerMetadata: SpeakerMetadata?
    var topicContext: String?
    var sharedFromSessionId: String?
    var syncState: SyncState? = nil

    var displayDuration: String {
        guard let durationSeconds else { return "--:--" }
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case photoCount = "photo_count"
        case resourceCount = "resource_count"
        case summary
        case transcriptLanguage = "transcript_language"
        case summaryLanguage = "summary_language"
        case speakerMetadata = "speaker_metadata_json"
        case topicContext = "topic_context"
        case sharedFromSessionId = "shared_from_session_id"
    }
}

struct AudioRecording: Codable {
    let id: String
    let fileUrl: String
    let durationSeconds: Int?
}

struct PhotoAsset: Identifiable, Codable {
    let id: String
    let fileUrl: String
    let takenAtOffsetSeconds: Int
    let ocrText: String?
    var transcriptSegment: TranscriptSegment?
}

struct TranscriptSegment: Identifiable, Codable {
    let id: String
    let startTimeSeconds: Int
    let endTimeSeconds: Int
    let text: String
}

struct Summary: Codable {
    let shortSummary: String
    let detailedSummary: String
    let keyPointsJson: [String]
    let actionItemsJson: [String]
    let highlightsJson: [String]?
    let language: String?

    enum CodingKeys: String, CodingKey {
        case shortSummary = "short_summary"
        case detailedSummary = "detailed_summary"
        case keyPointsJson = "key_points_json"
        case actionItemsJson = "action_items_json"
        case highlightsJson = "highlights_json"
        case language
    }
}

struct ResourceLink: Identifiable, Codable {
    let id: String
    let title: String
    let url: String
    let sourceName: String
    let description: String
}

struct SessionDetail: Codable {
    let session: Session
    let audio: AudioRecording?
    let photos: [PhotoAsset]
    let transcript: [TranscriptSegment]
    let summary: Summary?
    let resources: [ResourceLink]
    let chatMessages: [ChatMessage]
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct User: Codable { let id: String; let email: String }

struct SpeakerMetadata: Codable {
    var count: Int?
    var speakers: [SpeakerInfo]

    init(count: Int? = nil, speakers: [SpeakerInfo] = []) {
        self.count = count
        self.speakers = speakers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        speakers = try container.decodeIfPresent([SpeakerInfo].self, forKey: .speakers) ?? []
    }
}

struct SpeakerInfo: Codable, Identifiable {
    var id: String { name + (role ?? "") }
    var name: String
    var role: String?
}

enum ChatRole: String, Codable { case user, assistant }

enum ChatMessageStatus: String, Codable {
    case queued
    case sending
    case sent
    case failed
}

struct Citation: Codable, Identifiable {
    var id: String { chunkId ?? UUID().uuidString }
    let chunkId: String?
    let startTimeSeconds: Int?
    let endTimeSeconds: Int?
    let text: String

    enum CodingKeys: String, CodingKey {
        case chunkId = "chunk_id"
        case startTimeSeconds = "start_time_seconds"
        case endTimeSeconds = "end_time_seconds"
        case text
    }
}

struct ExternalLink: Codable, Identifiable {
    var id: String { url }
    let title: String?
    let url: String
    let note: String?
}

struct ChatMessage: Identifiable, Codable {
    let id: String
    let role: ChatRole
    var content: String
    var citations: [Citation]?
    var externalLinks: [ExternalLink]?
    var language: String?
    var createdAt: Date?
    var status: ChatMessageStatus? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case citations = "citations_json"
        case externalLinks = "external_links_json"
        case language
        case createdAt = "created_at"
    }
}

struct ShareLinkResponse: Codable {
    let shareToken: String
    let shareLink: String
    let scope: String
}

struct ShareRecord: Codable {
    let id: String
    let sessionId: String
    let shareToken: String
    let scope: String
    let createdAt: Date?
    let expiresAt: Date?
}

struct SharePayload: Codable {
    let share: ShareRecord
    let session: Session
    let summary: Summary?
    let transcript: [TranscriptSegment]
    let resources: [ResourceLink]
    let externalLinks: [ExternalLink]

    enum CodingKeys: String, CodingKey {
        case share
        case session
        case summary
        case transcript
        case resources
        case externalLinks = "external_links"
    }
}
