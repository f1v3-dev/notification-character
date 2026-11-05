import AppKit
import CoreImage
import NotificationCore

final class WhiteBackgroundRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    func render(_ input: CIImage) -> NSImage? {
        let extent = input.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return nil }
        let scale = min(1, 384 / max(extent.width, extent.height))
        let image = input.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = max(1, Int(image.extent.width.rounded(.down))), height = max(1, Int(image.extent.height.rounded(.down)))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        context.render(image, toBitmap: &rgba, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: space)
        let output = WhiteBackgroundRemoval.remove(from: rgba, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    func render(poster: NSImage) -> NSImage? {
        guard let cgImage = poster.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return render(CIImage(cgImage: cgImage))
    }
}
