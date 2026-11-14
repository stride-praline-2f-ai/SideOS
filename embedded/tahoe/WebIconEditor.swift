import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable

struct TahoeWebIconDraft: @unchecked Sendable {
    let source: UIImage
    let crop: TahoeIconCrop
    func png(side: CGFloat) -> Data? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            source.draw(in: crop.imageRect(size: source.size, side: side))
        }.pngData()
    }
}

struct TahoePhotoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            guard (try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("sideos-photo-" + UUID().uuidString)
            try FileManager.default.copyItem(at: received.file, to: target)
            return TahoePhotoFile(url: target)
        }
    }
}

actor TahoeWebIconWriter {
    static let shared = TahoeWebIconWriter()
    private var revisions: [UUID: UInt64] = [:]
    func save(_ draft: TahoeWebIconDraft?, id: UUID, destination: URL, revision: UInt64) throws -> Data? {
        guard revision >= revisions[id, default: 0] else { return nil }; revisions[id] = revision
        guard let draft else { if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }; return nil }
        guard let icon = draft.png(side: 512), let source = draft.source.pngData() else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: destination, options: .atomic); return icon
    }
}

struct TahoeWebIconEditor: View {
    var link: TahoeWebLink? = nil
    var draft: TahoeWebIconDraft? = nil
    let save: (TahoeWebIconDraft?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var crop = TahoeIconCrop()
    @State private var dragStart: TahoeIconCrop?
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var loading = false
    @State private var message: String?
    private let side: CGFloat = 240
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(TahoeStrings.ui("Cancel")) { dismiss() }
                Spacer()
                Text(TahoeStrings.ui("Web App Icon")).font(.headline)
                Spacer()
                Button(TahoeStrings.ui("Save")) { if let image { save(TahoeWebIconDraft(source: image, crop: crop)); dismiss() } }
                    .disabled(image == nil || loading)
            }
            if let image {
                let rect = crop.imageRect(size: image.size, side: side)
                ZStack(alignment: .topLeading) {
                    Color.gray.opacity(0.15)
                    Image(uiImage: image).resizable().frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }.frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 55))
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        if dragStart == nil { dragStart = crop }
                        guard let start = dragStart else { return }
                        let initial = start.imageRect(size: image.size, side: side)
                        crop.x = min(1, max(-1, start.x + value.translation.width / max(1, (initial.width - side) / 2)))
                        crop.y = min(1, max(-1, start.y + value.translation.height / max(1, (initial.height - side) / 2)))
                    }.onEnded { _ in dragStart = nil })
                    .accessibilityLabel("Icon crop preview")
                VStack(alignment: .leading) {
                    Text(TahoeStrings.ui("Zoom")); Slider(value: $crop.zoom, in: 1...5).accessibilityLabel("Icon zoom")
                    Text(TahoeStrings.ui("Horizontal position")); Slider(value: $crop.x, in: -1...1).accessibilityLabel("Icon horizontal position")
                    Text(TahoeStrings.ui("Vertical position")); Slider(value: $crop.y, in: -1...1).accessibilityLabel("Icon vertical position")
                }.font(.caption)
                Button(TahoeStrings.ui("Reset Crop")) { crop = TahoeIconCrop() }
            } else {
                Image(systemName: "photo").font(.system(size: 64)).foregroundStyle(.secondary).frame(width: side, height: side)
            }
            HStack {
                PhotosPicker(selection: $photo, matching: .images) { Label(TahoeStrings.ui("Photos"), systemImage: "photo") }
                Button { importing = true } label: { Label(TahoeStrings.ui("Files"), systemImage: "folder") }
                if loading { ProgressView() }
            }.disabled(loading)
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            Button(TahoeStrings.ui("Use Website Icon")) { save(nil); dismiss() }.disabled(loading)
        }.padding(24).frame(minWidth: 340, idealWidth: 420, maxWidth: 540)
        .onAppear {
            if let draft { image = draft.source; crop = draft.crop }
            else if let link, link.customIcon == true {
                image = UIImage(contentsOfFile: Self.sourceURL(link.id).path) ?? link.iconData.flatMap { UIImage(data: $0) }
                if FileManager.default.fileExists(atPath: Self.sourceURL(link.id).path) {
                    crop = TahoeIconCrop(zoom: link.iconZoom ?? 1, x: link.iconOffsetX ?? 0, y: link.iconOffsetY ?? 0)
                }
            } else if let link { image = link.iconData.flatMap { UIImage(data: $0) } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            Task {
                loading = true; message = nil
                defer { loading = false }
                do {
                    let decoded = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25_000_000 else { throw CocoaError(.fileReadTooLarge) }
                        return try Self.decode(Data(contentsOf: url))
                    }.value
                    image = decoded; crop = TahoeIconCrop()
                } catch { message = "Could not read this image. Try a JPEG, PNG or HEIC under 25 MB." }
            }
        }
        .task(id: photo) {
            guard let photo else { return }
            loading = true; message = nil
            defer { loading = false }
            do {
                guard let file = try await photo.loadTransferable(type: TahoePhotoFile.self) else { throw CocoaError(.fileReadCorruptFile) }
                defer { try? FileManager.default.removeItem(at: file.url) }
                let decoded = try await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                    return UIImage(cgImage: image)
                }.value
                guard !Task.isCancelled else { return }
                image = decoded; crop = TahoeIconCrop()
            } catch { if !Task.isCancelled { message = "Could not read this photo. Try an image under 25 MB." } }
        }
    }
    nonisolated static func decode(_ data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return UIImage(cgImage: thumbnail)
    }
    static func sourceURL(_ id: UUID) -> URL { TahoeStorage.root.appendingPathComponent("web-icons", isDirectory: true).appendingPathComponent(id.uuidString + ".png") }
}
