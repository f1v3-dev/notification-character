import Testing
@testable import NotificationCore

struct WhiteBackgroundRemovalTests {
    @Test func removesOnlyEdgeConnectedWhiteAndKeepsEnclosedWhiteDetails() {
        let white: [UInt8] = [255, 255, 255, 255], orange: [UInt8] = [255, 100, 0, 255]
        var image = Array(repeating: white, count: 25)
        for y in 1...3 { for x in 1...3 { image[y * 5 + x] = orange } }
        image[12] = white
        let output = WhiteBackgroundRemoval.remove(from: image.flatMap { $0 }, width: 5, height: 5)
        #expect(output[3] == 0)
        #expect(Array(output[48..<52]) == white)
        #expect(Array(output[24..<28]) == orange)
    }
    @Test func preservesOpaqueArtworkWithoutAWhiteBackground() {
        let rgba: [UInt8] = [30, 120, 100, 255, 20, 80, 60, 255]
        #expect(WhiteBackgroundRemoval.remove(from: rgba, width: 2, height: 1) == rgba)
    }
    @Test func removesWhiteFringeWithPremultipliedAlphaAndRetainsExistingTransparency() {
        let rgba: [UInt8] = [255, 255, 255, 255, 255, 220, 205, 255, 0, 0, 0, 0]
        let result = WhiteBackgroundRemoval.remove(from: rgba, width: 3, height: 1)
        #expect(result[3] == 0)
        #expect(result[7] > 0 && result[7] < 255)
        #expect(result[4] <= result[7])
        #expect(result[11] == 0)
    }
    @Test func invalidOrOversizedFramesDoNotCrash() {
        #expect(WhiteBackgroundRemoval.remove(from: [1, 2], width: 1, height: 1) == [1, 2])
        #expect(WhiteBackgroundRemoval.remove(from: [], width: 0, height: 0).isEmpty)
        #expect(WhiteBackgroundRemoval.remove(from: [], width: 10_000, height: 10_000).isEmpty)
    }
}
