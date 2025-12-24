import SwiftUI
import UIKit

struct RecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = RecordingViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showCamera = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            HStack {
                Capsule()
                    .fill(AppColors.accent)
                    .frame(width: 48, height: 6)
                    .opacity(0.8)
                    .padding(.top, Spacing.md)
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("New Session")
                    .font(Typography.titleL)
                    .foregroundColor(AppColors.textPrimary)
                TextField("Session title", text: $viewModel.sessionTitle)
                    .padding()
                    .background(AppColors.card)
                    .cornerRadius(12)
                    .foregroundColor(AppColors.textPrimary)
            }
            timer
            recordControls
            photoStrip
            Spacer()
            Button("Close") { dismiss() }
                .foregroundColor(AppColors.textSecondary)
                .padding(.bottom, Spacing.lg)
        }
        .padding(Spacing.xl)
        .background(AppColors.background)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                Task { await viewModel.addCapturedPhoto(image: image) }
            }
        }
        .alert("Recording", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            if viewModel.showMicrophoneSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var timer: some View {
        VStack(spacing: Spacing.sm) {
            Text(viewModel.isRecording ? "Recording" : "Ready")
                .foregroundColor(AppColors.textSecondary)
            Text(viewModel.elapsedString)
                .font(Typography.titleXL)
                .foregroundColor(AppColors.textPrimary)
            if !networkMonitor.isOnline {
                Text("Offline mode: will sync when back online.")
                    .font(Typography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .animation(.easeInOut, value: viewModel.isRecording)
    }

    private var recordControls: some View {
        HStack(spacing: Spacing.xl) {
            Button(action: { Task { await capturePhoto() } }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(viewModel.isRecording ? AppColors.textPrimary : AppColors.textSecondary)
                    .padding()
                    .background(AppColors.card, in: Circle())
                    .opacity(viewModel.isRecording ? 1.0 : 0.6)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isRecording)
            Spacer()
            Button(action: { Task { await toggleRecording() } }) {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? AppColors.destructive : AppColors.accent)
                        .frame(width: 96, height: 96)
                        .shadow(color: AppColors.shadow, radius: 14, x: 0, y: 10)
                        .scaleEffect(viewModel.isRecording ? 1.05 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: viewModel.isRecording)
                    Circle()
                        .stroke(AppColors.accentSoft, lineWidth: 12)
                        .frame(width: 128, height: 128)
                        .opacity(viewModel.isRecording ? 0.3 : 0.12)
                        .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: viewModel.isRecording)
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppColors.background)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Hints")
                    .font(Typography.callout)
                    .foregroundColor(AppColors.textPrimary)
                Text("Tap camera to capture slides while recording. Audio keeps running.")
                    .font(Typography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(viewModel.capturedPhotos) { photo in
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.vertical, Spacing.md)
        }
    }

    private func toggleRecording() async {
        if viewModel.isRecording {
            await viewModel.stopRecording()
            if viewModel.isProcessing {
                // Use subtle delay to show processing indicator on caller screen
            }
            dismiss()
        } else {
            await viewModel.startRecording()
        }
    }

    private func capturePhoto() async {
#if targetEnvironment(simulator)
        await viewModel.addPhotoPlaceholder()
#else
        showCamera = true
#endif
    }
}
