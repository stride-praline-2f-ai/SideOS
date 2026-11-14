import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor final class TahoeWallpaperPhoto: ObservableObject {
    static let shared = TahoeWallpaperPhoto()
    @Published private(set) var image: UIImage?
    @Published private(set) var loading = false
    private static var file: URL { TahoeStorage.root.appendingPathComponent("wallpaper.jpg") }
    init() { image = UIImage(contentsOfFile: Self.file.path) }
    func importImage(_ url: URL) async throws {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let destination = Self.file
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2560
                  ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            guard let data = CFDataCreateMutable(nil, 0),
                  let output = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(output, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (data as Data).write(to: destination, options: .atomic)
        }.value
        image = UIImage(contentsOfFile: destination.path)
        TahoePreferences.shared.value.wallpaper = "custom"
    }
}
