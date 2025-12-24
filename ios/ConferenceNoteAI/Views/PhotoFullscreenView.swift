import SwiftUI

struct PhotoFullscreenView: View {
    let photo: PhotoAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Spacer()
                PhotoAssetImageView(fileUrl: photo.fileUrl, scaling: .fit)
                    .cornerRadius(16)
                    .shadow(radius: 20)
                    .transition(.scale.combined(with: .opacity))
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Taken at \(photo.takenAtOffsetSeconds)s")
                        .foregroundColor(.white.opacity(0.8))
                        .font(Typography.caption)
                    if let transcript = photo.transcriptSegment?.text {
                        Text(transcript)
                            .font(Typography.body)
                            .foregroundColor(.white)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer()
            }
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .padding(12)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
            .padding()
            .foregroundColor(.white)
        }
    }
}
