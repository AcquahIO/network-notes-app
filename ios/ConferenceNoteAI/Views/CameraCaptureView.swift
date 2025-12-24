import AVFoundation
import SwiftUI

final class CameraController: NSObject, ObservableObject {
    enum CameraError: LocalizedError {
        case unauthorized
        case cameraUnavailable
        case captureInProgress
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Camera access is required to capture slide photos."
            case .cameraUnavailable:
                return "No camera is available on this device."
            case .captureInProgress:
                return "Please wait for the current photo to finish capturing."
            case .captureFailed:
                return "Unable to capture a photo."
            }
        }
    }

    @Published var isAuthorized = false
    @Published var isRunning = false
    @Published var errorMessage: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "ConferenceNoteAI.camera.session")
    private let output = AVCapturePhotoOutput()
    private var isConfigured = false
    private var captureCompletion: ((Result<UIImage, Error>) -> Void)?

    func requestAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await MainActor.run { self.isAuthorized = true }
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
            }
            await MainActor.run { self.isAuthorized = granted }
            if !granted { await setError(CameraError.unauthorized) }
            return granted
        default:
            await MainActor.run { self.isAuthorized = false }
            await setError(CameraError.unauthorized)
            return false
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.isConfigured {
                    try self.configure()
                    self.isConfigured = true
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                    DispatchQueue.main.async { self.isRunning = true }
                }
            } catch {
                Task { await self.setError(error) }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.isRunning = false }
            }
        }
    }

    func capturePhoto(completion: @escaping (Result<UIImage, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.captureCompletion == nil else {
                DispatchQueue.main.async { completion(.failure(CameraError.captureInProgress)) }
                return
            }

            self.captureCompletion = completion

            let settings = AVCapturePhotoSettings()
            if self.output.availablePhotoCodecTypes.contains(.hevc) {
                settings.isHighResolutionPhotoEnabled = true
            }
            settings.flashMode = .off
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard session.canAddInput(input) else { throw CameraError.cameraUnavailable }
        session.addInput(input)

        guard session.canAddOutput(output) else { throw CameraError.cameraUnavailable }
        session.addOutput(output)
        output.isHighResolutionCaptureEnabled = true

        session.commitConfiguration()
    }

    private func setError(_ error: Error) async {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        await MainActor.run { self.errorMessage = message }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result: Result<UIImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = .success(image)
        } else {
            result = .failure(CameraError.captureFailed)
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let completion = self.captureCompletion
            self.captureCompletion = nil
            DispatchQueue.main.async {
                completion?(result)
            }
        }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

struct CameraCaptureView: View {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            if camera.isAuthorized {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                AppTheme.backgroundGradient().ignoresSafeArea()
                VStack(spacing: Spacing.md) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Camera permission needed")
                        .font(Typography.titleM)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Enable Camera access in Settings to capture slide photos.")
                        .font(Typography.body)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.xl)
            }

            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .padding(12)
                            .background(AppColors.card.opacity(0.9), in: Circle())
                    }
                    .foregroundColor(AppColors.textPrimary)

                    Spacer()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

                Spacer()

                Button(action: capture) {
                    ZStack {
                        Circle()
                            .fill(AppColors.textPrimary.opacity(0.15))
                            .frame(width: 84, height: 84)
                        Circle()
                            .stroke(AppColors.textPrimary, lineWidth: 3)
                            .frame(width: 68, height: 68)
                        if isCapturing {
                            ProgressView().tint(AppColors.textPrimary)
                        }
                    }
                }
                .disabled(!camera.isAuthorized || isCapturing)
                .padding(.bottom, Spacing.xl)
            }
        }
        .task {
            let granted = await camera.requestAccessIfNeeded()
            if granted { camera.start() }
        }
        .onDisappear { camera.stop() }
        .alert("Camera", isPresented: Binding(get: { camera.errorMessage != nil }, set: { if !$0 { camera.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(camera.errorMessage ?? "")
        }
    }

    private func capture() {
        guard camera.isAuthorized else { return }
        isCapturing = true
        camera.capturePhoto { result in
            isCapturing = false
            switch result {
            case .success(let image):
                onCapture(image)
                dismiss()
            case .failure(let error):
                camera.errorMessage = error.localizedDescription
            }
        }
    }
}
