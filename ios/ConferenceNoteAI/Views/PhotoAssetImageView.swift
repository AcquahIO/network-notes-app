import SwiftUI
import UIKit

struct PhotoAssetImageView: View {
    enum Scaling { case fill, fit }

    let fileUrl: String
    var scaling: Scaling = .fill

    @State private var localImage: UIImage?

    var body: some View {
        Group {
            if let url = URL(string: fileUrl), url.isFileURL {
                if let localImage {
                    imageView(Image(uiImage: localImage))
                } else {
                    placeholder
                        .task { await loadLocal(from: url) }
                }
            } else if let url = URL(string: fileUrl) {
                AsyncImage(url: url) { image in
                    imageView(image)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
    }

    @ViewBuilder
    private func imageView(_ image: Image) -> some View {
        switch scaling {
        case .fill:
            image.resizable().scaledToFill()
        case .fit:
            image.resizable().scaledToFit()
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppColors.card)
            .overlay(ProgressView().tint(AppColors.accent))
    }

    private func loadLocal(from url: URL) async {
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
        localImage = image
    }
}
