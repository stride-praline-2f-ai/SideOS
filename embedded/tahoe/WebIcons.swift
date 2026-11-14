import UIKit
import ImageIO

actor TahoeFaviconLoader {
    static let shared = TahoeFaviconLoader()
    private var cache: [URL: Data] = [:]
    private var order: [URL] = []
    private let network: URLSession = {
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.timeoutIntervalForRequest = 6
        return URLSession(configuration: config)
    }()
    func load(_ candidates: [URL]) async -> Data? {
        for url in candidates.prefix(8) where ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.pathExtension.lowercased() != "svg" {
            if let data = cache[url] { order.removeAll { $0 == url }; order.append(url); return data }
            do {
                try Task.checkCancellation()
                let (file, response) = try await network.download(from: url)
                defer { try? FileManager.default.removeItem(at: file) }
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                      response.mimeType != "image/svg+xml",
                      (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_048_576,
                      let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary),
                      let data = UIImage(cgImage: image).pngData() else { continue }
                cache[url] = data; order.append(url)
                while order.count > 64 { cache.removeValue(forKey: order.removeFirst()) }
                return data
            } catch is CancellationError { return nil }
            catch { continue }
        }
        return nil
    }
}
