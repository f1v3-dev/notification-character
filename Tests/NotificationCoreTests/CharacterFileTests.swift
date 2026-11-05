import Foundation
import Testing
@testable import NotificationCore

struct CharacterFileTests {
    private let valid = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <defs><linearGradient id="g"><stop stop-color="#bfe"/></linearGradient><path id="p" d="M0 0h80v80H0z"/></defs>
        <use href="#p" fill="url(#g)"/></svg>
        """.utf8)
    @Test func acceptsSelfContainedSVGWithGradientsAndLocalReferences() throws {
        try CharacterFileValidation.validate(valid, name: "friend.SVG")
    }
    @Test func rejectsMalformedAndNonSVGFiles() {
        for source in ["<svg", "<html/>", "", "<!DOCTYPE svg [<!ENTITY x 'a'>]><svg>&x;</svg>"] {
            #expect(throws: (any Error).self) { try CharacterFileValidation.validate(Data(source.utf8), name: "friend.svg") }
        }
        #expect(throws: (any Error).self) { try CharacterFileValidation.validate(valid, name: "friend.txt") }
        #expect(throws: (any Error).self) { try CharacterFileValidation.validate(Data(repeating: 1, count: CharacterFileValidation.maximumBytes + 1), name: "friend.png") }
    }
    @Test func rejectsScriptsExternalResourcesAndStylesheets() {
        for body in [
            "<script>alert(1)</script>", "<path onload='a()'/>",
            "<image href='https://example.com/image.png'/>", "<use href='other.svg#cat'/>",
            "<path style='fill:url(https://example.com/pattern)'/>",
            "<style><![CDATA[@import 'https://example.com/x.css';]]></style>",
            "<foreignObject/>", "<animate attributeName='x'/>",
        ] {
            let data = Data(("<svg xmlns='http://www.w3.org/2000/svg'>" + body + "</svg>").utf8)
            #expect(throws: (any Error).self) { try CharacterFileValidation.validate(data, name: "friend.svg") }
        }
        let externalStyle = Data("<?xml-stylesheet href='https://example.com/x.css'?><svg/>".utf8)
        #expect(throws: (any Error).self) { try CharacterFileValidation.validate(externalStyle, name: "friend.svg") }
    }
    @Test func keepsImportedDataAndSelectionAcrossReloadAndReplacesOldCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CharacterFileStore(directory: folder)
        let first = try store.save(valid, originalName: "my-friend.svg")
        #expect(first.originalName == "my-friend.svg")
        #expect(try Data(contentsOf: store.selectedURL!) == valid)
        let reloaded = CharacterFileStore(directory: folder)
        #expect(reloaded.selection == first)
        let second = try reloaded.save(valid, originalName: "other.svg")
        #expect(second.filename != first.filename)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(first.filename).path))
        #expect(throws: (any Error).self) { try store.save(Data("broken".utf8), originalName: "bad.svg") }
        #expect(store.selection == second)
    }
    @Test func refusesSelectionOutsideManagedDirectory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{\"filename\":\"../../outside.svg\",\"originalName\":\"outside\"}".utf8).write(to: folder.appendingPathComponent("selection.json"))
        #expect(CharacterFileStore(directory: folder).selection == nil)
    }
    @Test func acceptsAnimationExtensionsAndUsesSeparateVideoSizeLimit() throws {
        for ext in ["gif", "mp4", "mov"] {
            try CharacterFileValidation.validate(Data([1, 2, 3]), name: "friend." + ext)
        }
        #expect(CharacterFileValidation.byteLimit(for: "friend.gif") == 10 * 1024 * 1024)
        #expect(CharacterFileValidation.byteLimit(for: "friend.MP4") == 50 * 1024 * 1024)
    }
}
