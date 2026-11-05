import Foundation

/// Removes edge-connected near-white pixels, preserving enclosed white eyes/details.
/// Input/output are premultiplied RGBA bytes. Processing is bounded to preview-sized frames.
public enum WhiteBackgroundRemoval {
    public static func remove(from rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0, width <= 1024, height <= 1024, rgba.count == width * height * 4 else { return rgba }
        let count = width * height
        var background = [UInt8](repeating: 0, count: count)
        var queue = [Int](); queue.reserveCapacity(count)
        func white(_ pixel: Int) -> Bool {
            let p = pixel * 4
            let low = min(rgba[p], rgba[p + 1], rgba[p + 2])
            let high = max(rgba[p], rgba[p + 1], rgba[p + 2])
            return rgba[p + 3] >= 240 && low >= 245 && Int(high) - Int(low) <= 18
        }
        func visit(_ pixel: Int) {
            if background[pixel] == 0 && white(pixel) { background[pixel] = 1; queue.append(pixel) }
        }
        for x in 0..<width { visit(x); visit((height - 1) * width + x) }
        for y in 0..<height { visit(y * width); visit(y * width + width - 1) }
        var head = 0
        while head < queue.count {
            let pixel = queue[head]; head += 1
            let x = pixel % width
            if x > 0 { visit(pixel - 1) }
            if x < width - 1 { visit(pixel + 1) }
            if pixel >= width { visit(pixel - width) }
            if pixel + width < count { visit(pixel + width) }
        }
        var output = rgba
        for pixel in 0..<count {
            let p = pixel * 4
            if background[pixel] == 1 {
                output[p] = 0; output[p + 1] = 0; output[p + 2] = 0; output[p + 3] = 0
            } else if rgba[p + 3] >= 240 {
                let x = pixel % width
                let adjacent = (x > 0 && background[pixel - 1] == 1) || (x < width - 1 && background[pixel + 1] == 1)
                    || (pixel >= width && background[pixel - width] == 1) || (pixel + width < count && background[pixel + width] == 1)
                let low = min(rgba[p], rgba[p + 1], rgba[p + 2])
                if adjacent && low >= 200 {
                    let alpha = max(0, min(1, Double(255 - Int(low)) / 55))
                    let whiteContribution = Int((1 - alpha) * 255)
                    let outputAlpha = Int((Double(rgba[p + 3]) * alpha).rounded())
                    for channel in 0..<3 { output[p + channel] = UInt8(min(outputAlpha, max(0, Int(rgba[p + channel]) - whiteContribution))) }
                    output[p + 3] = UInt8(outputAlpha)
                }
            }
        }
        return output
    }
}
