import Foundation
import Combine
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var sessionTitle: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var elapsed: TimeInterval = 0
    @Published var capturedPhotos: [CapturedPhoto] = []
    @Published var errorMessage: String?
    @Published var showMicrophoneSettings: Bool = false

    private let recorder = RecordingService()
    private let photoService = PhotoCaptureService()
    private let api = APIClient.shared
    private let store = LocalStore.shared
    private let syncManager = SyncManager.shared
    private let network = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentSessionId: String?
    private var recordingFileURL: URL?
    private var recordingStartedAt: Date?

    init() {
        recorder.$elapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.elapsed = $0 }
            .store(in: &cancellables)

        recorder.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isRecording = $0 }
            .store(in: &cancellables)

        photoService.$captured
            .receive(on: DispatchQueue.main)
            .sink { [weak self] photos in self?.capturedPhotos = photos }
            .store(in: &cancellables)
    }

    func startRecording() async {
        showMicrophoneSettings = false
        do {
            try await recorder.requestMicrophonePermission()
            let title = sessionTitle.isEmpty ? "Untitled Session" : sessionTitle
            if network.isOnline {
                let session = try await api.createSession(title: title)
                currentSessionId = session.id
            } else {
                let localId = "local-\(UUID().uuidString)"
                let session = Session(
                    id: localId,
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
                    syncState: .recordedPendingUpload
                )
                let detail = SessionDetail(session: session, audio: nil, photos: [], transcript: [], summary: nil, resources: [], chatMessages: [])
                await store.saveSessionDetail(detail, syncState: session.syncState)
                await syncManager.enqueue(LocalStore.SyncJob(
                    id: UUID().uuidString,
                    type: .createSession,
                    sessionId: localId,
                    title: title,
                    audioFilePath: nil,
                    audioDuration: nil,
                    photoFilePath: nil,
                    takenAtSeconds: nil,
                    chatMessage: nil,
                    chatLanguage: nil,
                    includeExternalReading: nil,
                    attempts: 0,
                    createdAt: Date()
                ))
                currentSessionId = localId
            }
            recordingFileURL = try recorder.startRecording()
            recordingStartedAt = Date()
        } catch {
            showMicrophoneSettings = error is RecordingService.RecordingError
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard let sessionId = currentSessionId else { return }
        let result = recorder.stopRecording()
        recordingFileURL = result?.url
        recordingStartedAt = nil
        isProcessing = true
        do {
            if let result {
                if network.isOnline {
                    _ = try await api.uploadAudio(sessionId: sessionId, fileUrl: result.url.absoluteString, duration: result.duration)
                } else {
                    await syncManager.enqueue(LocalStore.SyncJob(
                        id: UUID().uuidString,
                        type: .uploadAudio,
                        sessionId: sessionId,
                        title: nil,
                        audioFilePath: result.url.absoluteString,
                        audioDuration: result.duration,
                        photoFilePath: nil,
                        takenAtSeconds: nil,
                        chatMessage: nil,
                        chatLanguage: nil,
                        includeExternalReading: nil,
                        attempts: 0,
                        createdAt: Date()
                    ))
                    await store.updateSyncState(sessionId: sessionId, state: .recordedPendingUpload)
                    if let detail = await store.loadSessionDetail(sessionId: sessionId) {
                        var session = detail.session
                        session.status = .processing
                        session.endedAt = Date()
                        session.durationSeconds = result.duration
                        let updated = SessionDetail(
                            session: session,
                            audio: detail.audio,
                            photos: detail.photos,
                            transcript: detail.transcript,
                            summary: detail.summary,
                            resources: detail.resources,
                            chatMessages: detail.chatMessages
                        )
                        await store.saveSessionDetail(updated, syncState: session.syncState)
                    }
                }
            }
            isProcessing = false
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    func addCapturedPhoto(image: UIImage) async {
        let photo = CapturedPhoto(image: image, timestamp: Date())
        photoService.captured.insert(photo, at: 0)

        guard isRecording, let sessionId = currentSessionId, let fileURL = photo.fileURL else { return }

        let takenAtSeconds: Int = {
            if let startedAt = recordingStartedAt {
                return max(0, Int(Date().timeIntervalSince(startedAt)))
            }
            return Int(elapsed)
        }()

        do {
            if network.isOnline {
                _ = try await api.uploadPhoto(sessionId: sessionId, fileUrl: fileURL.absoluteString, takenAtSeconds: takenAtSeconds)
            } else {
                await syncManager.enqueue(LocalStore.SyncJob(
                    id: UUID().uuidString,
                    type: .uploadPhoto,
                    sessionId: sessionId,
                    title: nil,
                    audioFilePath: nil,
                    audioDuration: nil,
                    photoFilePath: fileURL.absoluteString,
                    takenAtSeconds: takenAtSeconds,
                    chatMessage: nil,
                    chatLanguage: nil,
                    includeExternalReading: nil,
                    attempts: 0,
                    createdAt: Date()
                ))
            }
            if let detail = await store.loadSessionDetail(sessionId: sessionId) {
                var updatedPhotos = detail.photos
                let localPhoto = PhotoAsset(
                    id: UUID().uuidString,
                    fileUrl: fileURL.absoluteString,
                    takenAtOffsetSeconds: takenAtSeconds,
                    ocrText: nil,
                    transcriptSegment: nil
                )
                updatedPhotos.append(localPhoto)
                var session = detail.session
                session.photoCount = updatedPhotos.count
                let updated = SessionDetail(
                    session: session,
                    audio: detail.audio,
                    photos: updatedPhotos,
                    transcript: detail.transcript,
                    summary: detail.summary,
                    resources: detail.resources,
                    chatMessages: detail.chatMessages
                )
                await store.saveSessionDetail(updated, syncState: detail.session.syncState)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPhotoPlaceholder() async {
#if targetEnvironment(simulator)
        // Simulator fallback: inject a placeholder photo so UI/upload flows can be tested.
        // Create a simple 1x1 PNG image data as a stand-in.
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII="

        let image: UIImage = {
            if let data = Data(base64Encoded: pngBase64), let img = UIImage(data: data) {
                return img
            }
            // Fallback to a 1x1 solid color image if decoding fails
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
            return renderer.image { ctx in
                UIColor.lightGray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }()

        await addCapturedPhoto(image: image)
#else
        // On device, leave as a noop here. The real camera flow should be triggered elsewhere.
        return
#endif
    }

    var elapsedString: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
