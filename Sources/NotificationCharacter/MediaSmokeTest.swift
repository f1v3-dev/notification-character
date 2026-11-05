import AppKit
import AVFoundation
import ImageIO
import NotificationCore

enum MediaSmokeTest {
    @MainActor static func run(video url: URL) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CharacterMedia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gifURL = root.appendingPathComponent("animated.gif")
        let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, "com.compuserve.gif" as CFString, 2, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for color in [NSColor.systemRed, NSColor.systemBlue] {
            context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            CGImageDestinationAddImage(gif, context.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.12]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(gif))
        let animated = try CharacterMedia.read(from: gifURL)
        let gifView = CatView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
        gifView.setMedia(image: animated.image); gifView.isPlaybackActive = true
        precondition(gifView.gifFrameCount == 2)
        func gifColor() -> NSColor {
            let rep = gifView.bitmapImageRepForCachingDisplay(in: gifView.bounds)!
            gifView.cacheDisplay(in: gifView.bounds, to: rep)
            return rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
        }
        let first = gifColor()
        gifView.advanceMedia(dt: 0.13); precondition(gifView.gifFrame == 1)
        let second = gifColor(); precondition(abs(first.redComponent - second.redComponent) > 0.2)
        gifView.advanceMedia(dt: 0.12); precondition(gifView.gifFrame == 0)
        gifView.isPlaybackActive = false; gifView.advanceMedia(dt: 0.2); precondition(gifView.gifFrame == 0)
        print("PASS: GIF advances both frames, loops and pauses when hidden")

        let media = try await CharacterMedia.readMedia(from: url)
        guard media.videoURL != nil else { throw CharacterFileError.unsupportedVideo }
        let store = CharacterFileStore(directory: root.appendingPathComponent("saved"))
        try store.save(media.data, originalName: url.lastPathComponent)
        let reloaded = try await CharacterMedia.readMedia(from: store.selectedURL!)
        let panel = CatPanel(contentRect: NSRect(x: 30, y: 80, width: 160, height: 160), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.ignoresMouseEvents = true
        let view = CatView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
        panel.contentView = view
        view.removeWhiteBackground = true
        view.setMedia(image: reloaded.image, videoURL: reloaded.videoURL, transform: reloaded.transform)
        panel.orderFrontRegardless(); view.layoutSubtreeIfNeeded(); view.isPlaybackActive = true
        let duration = try await AVURLAsset(url: store.selectedURL!).load(.duration).seconds
        print("Video duration: \(duration)s"); fflush(stdout)
        let end = ProcessInfo.processInfo.systemUptime + min(30, duration * 2 + 1)
        var advanced = false
        while ProcessInfo.processInfo.systemUptime < end {
            try await Task.sleep(nanoseconds: 50_000_000)
            view.advanceMedia(dt: 0.05)
            if (view.player?.currentTime().seconds ?? 0) > 0.02 { advanced = true }
        }
        precondition(advanced && view.player?.isMuted == true)
        precondition(view.processedVideoFrames > 0 && view.renderedVideoFrame != nil)
        let cutout = view.renderedVideoFrame!
        let rep = NSBitmapImageRep(cgImage: cutout.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        precondition((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0)
        if duration < 14 { precondition(view.videoLoopCount >= 1) }
        let loops = view.videoLoopCount
        view.isPlaybackActive = false
        precondition(view.player?.rate == 0)
        view.setMedia(image: nil); precondition(view.player == nil)
        panel.orderOut(nil)
        print("PASS: MP4 managed copy, muted playback, \(loops) loops, \(view.processedVideoFrames) transparent frames, pause and default restore")
    }
}
