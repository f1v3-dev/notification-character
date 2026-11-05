import AppKit
import AVFoundation
import CoreImage

final class CatView: NSView {
    var phase: Double = 0
    var moving = false
    var look: CGFloat = 0
    var hasNotification = false { didSet { videoNotice?.isHidden = removeWhiteBackground || !hasNotification } }
    var characterImage: NSImage? {
        didSet {
            gifFrame = 0; gifElapsed = 0
            gif = characterImage?.representations.compactMap { $0 as? NSBitmapImageRep }.first
            gif?.setProperty(.currentFrame, withValue: 0)
            needsDisplay = true
        }
    }
    var isPlaybackActive = false { didSet { if oldValue != isPlaybackActive { isPlaybackActive ? player?.play() : player?.pause() } } }
    var videoLoopCount: Int { looper?.loopCount ?? 0 }
    private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoLayer: AVPlayerLayer?
    private var videoNotice: CALayer?
    private var gif: NSBitmapImageRep?
    private(set) var gifFrame = 0
    private var gifElapsed = 0.0
    var removeWhiteBackground = false {
        didSet {
            mediaGeneration += 1; processingGeneration = nil
            updateBackgroundRemoval()
        }
    }
    private let backgroundRenderer = WhiteBackgroundRenderer()
    private let frameQueue = DispatchQueue(label: "NotificationCharacter.VideoCutout", qos: .userInitiated)
    private var videoOutputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
    private var videoTransform = CGAffineTransform.identity
    private var mediaGeneration = 0
    private var processingGeneration: Int?
    private(set) var renderedVideoFrame: NSImage?
    private(set) var processedVideoFrames = 0
    var gifFrameCount: Int { gif?.value(forProperty: .frameCount) as? Int ?? 1 }

    func setMedia(image: NSImage?, videoURL: URL? = nil, transform: CGAffineTransform = .identity) {
        mediaGeneration += 1; processingGeneration = nil; videoOutputs = [:]; renderedVideoFrame = nil
        videoTransform = transform
        player?.pause(); looper?.disableLooping(); player?.removeAllItems()
        videoLayer?.removeFromSuperlayer(); videoNotice?.removeFromSuperlayer()
        videoLayer = nil; videoNotice = nil; looper = nil; player = nil
        characterImage = image
        if let videoURL {
            let item = AVPlayerItem(url: videoURL)
            let queue = AVQueuePlayer(); queue.isMuted = true; queue.volume = 0
            player = queue; looper = AVPlayerLooper(player: queue, templateItem: item)
            wantsLayer = true
            let video = AVPlayerLayer(player: queue); video.videoGravity = .resizeAspect; video.zPosition = 1
            layer?.addSublayer(video); videoLayer = video
            let notice = CALayer(); notice.zPosition = 2; notice.isHidden = !hasNotification
            layer?.addSublayer(notice); videoNotice = notice
            needsLayout = true
            updateBackgroundRemoval()
            if isPlaybackActive { queue.play() }
        }
    }
    func advanceMedia(dt: Double) {
        if isPlaybackActive && removeWhiteBackground { updateVideoFrame() }
        guard isPlaybackActive, let gif, gifFrameCount > 1 else { return }
        gifElapsed += max(0, min(dt, 0.25))
        for _ in 0..<10 {
            let rawDelay = gif.value(forProperty: .currentFrameDuration) as? Double ?? 0.1
            let delay = rawDelay >= 0.02 ? rawDelay : 0.1
            guard gifElapsed >= delay else { break }
            gifElapsed -= delay; gifFrame = (gifFrame + 1) % gifFrameCount
            gif.setProperty(.currentFrame, withValue: gifFrame)
            characterImage?.recache(); needsDisplay = true
        }
    }
    private func updateBackgroundRemoval() {
        videoLayer?.isHidden = removeWhiteBackground
        videoNotice?.isHidden = removeWhiteBackground || !hasNotification
        if player != nil, removeWhiteBackground, let poster = characterImage { renderedVideoFrame = backgroundRenderer.render(poster: poster) }
        else { renderedVideoFrame = nil }
        needsDisplay = true
    }
    private func updateVideoFrame() {
        guard processingGeneration == nil, let player, let item = player.currentItem else { return }
        let id = ObjectIdentifier(item)
        if videoOutputs[id] == nil {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            item.add(output); videoOutputs[id] = output
            let live = Set(player.items().map(ObjectIdentifier.init))
            videoOutputs = videoOutputs.filter { live.contains($0.key) }
        }
        guard let output = videoOutputs[id] else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let generation = mediaGeneration, transform = videoTransform
        processingGeneration = generation
        frameQueue.async { [weak self] in
            guard let self else { return }
            let frame = self.backgroundRenderer.render(CIImage(cvPixelBuffer: buffer).transformed(by: transform))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.processingGeneration == generation { self.processingGeneration = nil }
                guard self.mediaGeneration == generation, self.removeWhiteBackground, self.isPlaybackActive, let frame else { return }
                self.renderedVideoFrame = frame; self.processedVideoFrames += 1; self.needsDisplay = true
            }
        }
    }
    override func layout() {
        super.layout()
        guard let videoLayer, let videoNotice else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = NSRect(x: bounds.width * 8 / 112, y: bounds.height * 9 / 112, width: bounds.width * 96 / 112, height: bounds.height * 96 / 112)
        videoNotice.frame = NSRect(x: bounds.width * 84 / 112, y: bounds.height * 85 / 112, width: bounds.width * 24 / 112, height: bounds.height * 24 / 112)
        videoNotice.sublayers?.forEach { $0.removeFromSuperlayer() }
        let circle = CAShapeLayer(); circle.path = CGPath(ellipseIn: videoNotice.bounds, transform: nil)
        circle.fillColor = NSColor.systemRed.cgColor; circle.strokeColor = ink.cgColor; circle.lineWidth = 2
        videoNotice.addSublayer(circle)
        let mark = CATextLayer(); mark.string = "!"; mark.font = NSFont.boldSystemFont(ofSize: 16)
        mark.fontSize = videoNotice.bounds.height * 0.8; mark.alignmentMode = .center
        mark.foregroundColor = NSColor.white.cgColor; mark.contentsScale = window?.backingScaleFactor ?? 2
        mark.frame = videoNotice.bounds; videoNotice.addSublayer(mark)
        CATransaction.commit()
    }
    private let ink = NSColor(calibratedRed: 0.24, green: 0.18, blue: 0.16, alpha: 1)
    private let fur = NSColor(calibratedRed: 1, green: 0.67, blue: 0.34, alpha: 1)
    private let cream = NSColor(calibratedRed: 1, green: 0.94, blue: 0.80, alpha: 1)

    private func paint(_ path: NSBezierPath, _ color: NSColor, stroke: Bool = true) {
        color.setFill(); path.fill()
        if stroke { ink.setStroke(); path.lineWidth = 2.5; path.stroke() }
    }
    private func oval(_ rect: NSRect, _ color: NSColor, stroke: Bool = true) {
        paint(NSBezierPath(ovalIn: rect), color, stroke: stroke)
    }
    private func line(_ points: [NSPoint], width: CGFloat = 2.3, color: NSColor? = nil) {
        guard let first = points.first else { return }
        let p = NSBezierPath(); p.move(to: first)
        for point in points.dropFirst() { p.line(to: point) }
        p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
        (color ?? ink).setStroke(); p.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let t = NSAffineTransform()
        t.scaleX(by: bounds.width / 112, yBy: bounds.height / 112); t.concat()
        oval(NSRect(x: 29, y: 7, width: 58, height: 8), NSColor.black.withAlphaComponent(0.12), stroke: false)
        let bob = CGFloat(sin(phase * (moving ? 12 : 2))) * (moving ? 2 : 0.7)
        let bodyTransform = NSAffineTransform(); bodyTransform.translateX(by: 0, yBy: bob); bodyTransform.concat()

        if let image = renderedVideoFrame ?? characterImage {
            let scale = min(96 / image.size.width, 96 / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(x: 56 - size.width / 2, y: 57 - size.height / 2, width: size.width, height: size.height))
            drawNotificationBadge()
            return
        }

        // A curved tail behind the body.
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 78, y: 25))
        let wag = CGFloat(sin(phase * (moving ? 9 : 2.5))) * 6
        tail.curve(to: NSPoint(x: 97, y: 48 + wag), controlPoint1: NSPoint(x: 106, y: 15), controlPoint2: NSPoint(x: 108, y: 44 + wag))
        tail.lineCapStyle = .round; tail.lineWidth = 13; ink.setStroke(); tail.stroke()
        tail.lineWidth = 8; fur.setStroke(); tail.stroke()
        oval(NSRect(x: 33, y: 13, width: 49, height: 47), fur)
        oval(NSRect(x: 45, y: 18, width: 25, height: 29), cream, stroke: false)
        let stride = moving ? CGFloat(sin(phase * 12)) * 3 : 0
        oval(NSRect(x: 30, y: 10 + stride, width: 22, height: 13), fur)
        oval(NSRect(x: 63, y: 10 - stride, width: 22, height: 13), fur)

        // Ears are part of the head silhouette.
        let head = NSBezierPath(); head.move(to: NSPoint(x: 27, y: 61))
        head.curve(to: NSPoint(x: 29, y: 83), controlPoint1: NSPoint(x: 25, y: 68), controlPoint2: NSPoint(x: 26, y: 76))
        head.line(to: NSPoint(x: 29, y: 101)); head.line(to: NSPoint(x: 46, y: 90))
        head.curve(to: NSPoint(x: 70, y: 90), controlPoint1: NSPoint(x: 53, y: 93), controlPoint2: NSPoint(x: 63, y: 93))
        head.line(to: NSPoint(x: 88, y: 101)); head.line(to: NSPoint(x: 86, y: 81))
        head.curve(to: NSPoint(x: 88, y: 61), controlPoint1: NSPoint(x: 91, y: 74), controlPoint2: NSPoint(x: 92, y: 66))
        head.curve(to: NSPoint(x: 27, y: 61), controlPoint1: NSPoint(x: 83, y: 40), controlPoint2: NSPoint(x: 32, y: 40)); head.close()
        paint(head, fur)
        let pink = NSColor(calibratedRed: 1, green: 0.56, blue: 0.54, alpha: 1)
        for points: [NSPoint] in [[NSPoint(x: 33, y: 94), NSPoint(x: 34, y: 83), NSPoint(x: 41, y: 88)], [NSPoint(x: 83, y: 94), NSPoint(x: 81, y: 83), NSPoint(x: 74, y: 88)]] {
            let ear = NSBezierPath(); ear.move(to: points[0]); ear.line(to: points[1]); ear.line(to: points[2]); ear.close(); paint(ear, pink, stroke: false)
        }
        line([NSPoint(x: 53, y: 89), NSPoint(x: 54, y: 82)], width: 3)
        line([NSPoint(x: 62, y: 89), NSPoint(x: 61, y: 82)], width: 3)
        oval(NSRect(x: 37, y: 55, width: 40, height: 16), cream, stroke: false)
        let blink = phase.truncatingRemainder(dividingBy: 4.7) > 4.52
        if blink {
            line([NSPoint(x: 39, y: 73), NSPoint(x: 46, y: 73)])
            line([NSPoint(x: 69, y: 73), NSPoint(x: 76, y: 73)])
        } else {
            oval(NSRect(x: 40 + look, y: 69, width: 5, height: 9), ink, stroke: false)
            oval(NSRect(x: 70 + look, y: 69, width: 5, height: 9), ink, stroke: false)
        }
        oval(NSRect(x: 32, y: 63, width: 10, height: 5), pink.withAlphaComponent(0.65), stroke: false)
        oval(NSRect(x: 75, y: 63, width: 10, height: 5), pink.withAlphaComponent(0.65), stroke: false)
        let nose = NSBezierPath(); nose.move(to: NSPoint(x: 54, y: 66)); nose.line(to: NSPoint(x: 61, y: 66)); nose.line(to: NSPoint(x: 57.5, y: 62)); nose.close(); paint(nose, ink, stroke: false)
        line([NSPoint(x: 57.5, y: 62), NSPoint(x: 57.5, y: 59), NSPoint(x: 53, y: 57)], width: 1.7)
        line([NSPoint(x: 57.5, y: 59), NSPoint(x: 62, y: 57)], width: 1.7)
        line([NSPoint(x: 23, y: 66), NSPoint(x: 34, y: 64)], width: 1.6)
        line([NSPoint(x: 23, y: 60), NSPoint(x: 34, y: 61)], width: 1.6)
        line([NSPoint(x: 81, y: 64), NSPoint(x: 94, y: 66)], width: 1.6)
        line([NSPoint(x: 81, y: 61), NSPoint(x: 94, y: 60)], width: 1.6)
        line([NSPoint(x: 42, y: 47), NSPoint(x: 74, y: 47)], width: 5, color: NSColor(calibratedRed: 0.24, green: 0.65, blue: 0.57, alpha: 1))
        oval(NSRect(x: 53, y: 39, width: 10, height: 10), NSColor(calibratedRed: 1, green: 0.84, blue: 0.28, alpha: 1))
        line([NSPoint(x: 58, y: 42), NSPoint(x: 58, y: 44)], width: 1.2)
        drawNotificationBadge()
    }

    private func drawNotificationBadge() {
        guard videoLayer == nil || removeWhiteBackground else { return }
        if hasNotification {
            oval(NSRect(x: 84, y: 85, width: 24, height: 24), NSColor(calibratedRed: 0.96, green: 0.29, blue: 0.28, alpha: 1))
            let mark: NSString = "!"
            mark.draw(at: NSPoint(x: 93, y: 87), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.white])
        }
    }
}

final class CatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
