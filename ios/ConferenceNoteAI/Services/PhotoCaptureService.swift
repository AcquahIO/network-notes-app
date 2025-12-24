#if canImport(PhotosUI)
import Foundation
import SwiftUI
import PhotosUI
import UIKit

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let timestamp: Date
    var fileURL: URL? {
        do {
            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = base.appendingPathComponent("ConferenceNoteAI/Photos", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            let url = dir.appendingPathComponent("photo_\(id).jpg")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}

final class PhotoCaptureService: ObservableObject {
    @Published var captured: [CapturedPhoto] = []

    func loadImage(from item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) {
            await MainActor.run {
                let photo = CapturedPhoto(image: uiImage, timestamp: Date())
                self.captured.insert(photo, at: 0)
            }
        }
    }
}
#else
import Foundation
import SwiftUI
import UIKit

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image = UIImage()
    let timestamp = Date()
    var fileURL: URL? { nil }
}

final class PhotoCaptureService: ObservableObject {
    @Published var captured: [CapturedPhoto] = []
    func loadImage(from _: Any) async {
        // PhotosPicker not available on this platform/toolchain.
    }
}
#endif
