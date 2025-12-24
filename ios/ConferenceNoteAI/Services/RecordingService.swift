import Foundation
import AVFAudio

final class RecordingService: NSObject, ObservableObject {
    enum RecordingError: LocalizedError {
        case microphonePermissionDenied

        var errorDescription: String? {
            "Microphone access is required to record audio. Enable it in Settings."
        }
    }

    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func requestMicrophonePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw RecordingError.microphonePermissionDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            if !granted { throw RecordingError.microphonePermissionDenied }
        @unknown default:
            throw RecordingError.microphonePermissionDenied
        }
    }

    func startRecording() throws -> URL {
        guard AVAudioApplication.shared.recordPermission == .granted else { throw RecordingError.microphonePermissionDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let fileURL = try makeRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder?.delegate = self
        recorder?.prepareToRecord()
        recorder?.record()
        isRecording = true
        startTimer()
        return fileURL
    }

    func stopRecording() -> (url: URL, duration: Int)? {
        recorder?.stop()
        isRecording = false
        stopTimer()
        guard let recorder else { return nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (recorder.url, Int(recorder.currentTime))
    }

    private func startTimer() {
        elapsed = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed += 1
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func makeRecordingURL() throws -> URL {
        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("ConferenceNoteAI/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("session_\(UUID().uuidString).m4a")
    }
}

extension RecordingService: AVAudioRecorderDelegate {
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Recording error: \(error?.localizedDescription ?? "Unknown")")
    }
}
