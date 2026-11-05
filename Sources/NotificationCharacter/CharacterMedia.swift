import AppKit
import ImageIO
import AVFoundation
import NotificationCore

enum CharacterMedia {
    static func read(from url: URL) throws -> (data: Data, image: NSImage, videoURL: URL?, transform: CGAffineTransform) {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= CharacterFileValidation.byteLimit(for: url.lastPathComponent) else { throw CharacterFileError.tooLarge }
        let data = try Data(contentsOf: url)
        try CharacterFileValidation.validate(data, name: url.lastPathComponent)
        guard !CharacterFileValidation.isVideo(url.lastPathComponent) else { throw CharacterFileError.unsupportedVideo }
        if url.pathExtension.lowercased() != "svg" {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 32_000_000,
                  CGImageSourceGetCount(source) <= 600,
                  width * height * CGImageSourceGetCount(source) <= 60_000_000 else { throw CharacterFileError.unreadableImage }
        }
        guard let image = NSImage(data: data), image.isValid,
              image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0,
              image.size.width <= 1_000_000, image.size.height <= 1_000_000 else { throw CharacterFileError.unreadableImage }
        return (data, image, nil, .identity)
    }
    static func readMedia(from url: URL) async throws -> (data: Data, image: NSImage, videoURL: URL?, transform: CGAffineTransform) {
        guard CharacterFileValidation.isVideo(url.lastPathComponent) else { return try read(from: url) }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= CharacterFileValidation.byteLimit(for: url.lastPathComponent) else { throw CharacterFileError.tooLarge }
        let data = try Data(contentsOf: url)
        try CharacterFileValidation.validate(data, name: url.lastPathComponent)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let playable = try await asset.load(.isPlayable)
        guard playable, duration.isFinite, duration > 0, duration <= 60,
              let track = try await asset.loadTracks(withMediaType: .video).first else { throw CharacterFileError.unsupportedVideo }
        let dimensions = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        guard abs(dimensions.width) <= 4096, abs(dimensions.height) <= 4096 else { throw CharacterFileError.unsupportedVideo }
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        generator.maximumSize = NSSize(width: 512, height: 512)
        let (poster, _) = try await generator.image(at: .zero)
        return (data, NSImage(cgImage: poster, size: .zero), url, transform)
    }
}
