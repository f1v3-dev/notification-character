import Foundation

public enum CharacterFileError: LocalizedError {
    case unsupportedType, tooLarge, invalidSVG, externalSVGContent, unreadableImage, unsupportedVideo
    public var errorDescription: String? {
        switch self {
        case .unsupportedType: return "SVG, PNG, JPG, GIF, MP4, MOV 파일을 선택해 주세요."
        case .tooLarge: return "이미지는 10MB, 동영상은 50MB 이하의 파일을 선택해 주세요."
        case .invalidSVG: return "올바른 SVG 파일을 읽을 수 없습니다."
        case .externalSVGContent: return "이미지와 글꼴을 파일 안에 포함한 정적 SVG로 저장해 주세요. 외부 파일 참조나 스크립트는 지원하지 않습니다."
        case .unreadableImage: return "이 이미지를 표시할 수 없습니다. SVG를 다시 내보내거나 투명 PNG를 사용해 주세요."
        case .unsupportedVideo: return "재생 가능한 60초 이하의 MP4 또는 MOV 파일을 선택해 주세요."
        }
    }
}

/// SVG stays vector data and is rendered by AppKit, never by a browser.
public enum CharacterFileValidation {
    public static let maximumBytes = 10 * 1024 * 1024
    public static let extensions = ["svg", "png", "jpg", "jpeg", "gif", "mp4", "mov"]
    public static func isVideo(_ name: String) -> Bool { ["mp4", "mov"].contains((name as NSString).pathExtension.lowercased()) }
    public static func byteLimit(for name: String) -> Int { isVideo(name) ? 50 * 1024 * 1024 : maximumBytes }
    public static func validate(_ data: Data, name: String) throws {
        guard !data.isEmpty else { throw CharacterFileError.unreadableImage }
        guard data.count <= byteLimit(for: name) else { throw CharacterFileError.tooLarge }
        let ext = (name as NSString).pathExtension.lowercased()
        guard extensions.contains(ext) else { throw CharacterFileError.unsupportedType }
        if ext == "svg" {
            guard let xml = String(data: data, encoding: .utf8), !xml.lowercased().contains("<!doctype"), !xml.lowercased().contains("<!entity") else { throw CharacterFileError.invalidSVG }
            let inspector = SVGInspector()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = inspector
            guard parser.parse(), inspector.validRoot, !inspector.invalid else {
                throw inspector.external ? CharacterFileError.externalSVGContent : CharacterFileError.invalidSVG
            }
        }
    }
}

private final class SVGInspector: NSObject, XMLParserDelegate {
    var validRoot = false
    var invalid = false
    var external = false
    private var nodes = 0
    private var depth = 0
    private var styleDepth = 0
    private var css = ""
    private func allowedReference(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty || value.hasPrefix("#") || ["data:image/png;base64,", "data:image/jpeg;base64,"].contains(where: value.hasPrefix)
    }
    private func validCSS(_ text: String) -> Bool {
        let lowered = text.lowercased()
        guard !lowered.contains("@import"), !lowered.contains("\\") else { return false }
        let localURLsRemoved = lowered.replacingOccurrences(of: #"url\(\s*['"]?#[a-z0-9_.:-]+['"]?\s*\)"#, with: "", options: .regularExpression)
        return !localURLsRemoved.contains("url(")
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        nodes += 1; depth += 1
        if nodes == 1 { validRoot = name == "svg" && (namespaceURI == nil || namespaceURI == "http://www.w3.org/2000/svg") }
        if nodes > 20_000 || depth > 100 { invalid = true; parser.abortParsing(); return }
        if ["script", "foreignobject", "animate", "animatetransform", "animatemotion", "set"].contains(name.lowercased()) {
            invalid = true; external = true; parser.abortParsing(); return
        }
        if name.lowercased() == "style" { styleDepth = depth; css = "" }
        for (key, value) in attributes {
            let key = key.lowercased()
            if key.hasPrefix("on") || key == "xml:base" || ((key == "href" || key == "xlink:href") && !allowedReference(value)) || !validCSS(value) {
                invalid = true; external = true; parser.abortParsing(); return
            }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if styleDepth > 0 { css += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if styleDepth > 0 { css += String(decoding: CDATABlock, as: UTF8.self) } }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        if target.lowercased() == "xml-stylesheet" { invalid = true; external = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if depth == styleDepth {
            if !validCSS(css) { invalid = true; external = true; parser.abortParsing() }
            styleDepth = 0; css = ""
        }
        depth -= 1
    }
}

public struct CharacterFileSelection: Codable, Equatable {
    public let filename: String
    public let originalName: String
    public var validFilename: Bool {
        let file = filename as NSString
        return file.lastPathComponent == filename && UUID(uuidString: file.deletingPathExtension) != nil && CharacterFileValidation.extensions.contains(file.pathExtension)
    }
}

public struct CharacterFileStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var selection: CharacterFileSelection? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("selection.json")),
              let saved = try? JSONDecoder().decode(CharacterFileSelection.self, from: data), saved.validFilename,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(saved.filename).path) else { return nil }
        return saved
    }
    public var selectedURL: URL? { selection.map { directory.appendingPathComponent($0.filename) } }
    /// Called only after the app has also decoded the image successfully.
    @discardableResult public func save(_ data: Data, originalName: String) throws -> CharacterFileSelection {
        try CharacterFileValidation.validate(data, name: originalName)
        let old = selection
        let ext = (originalName as NSString).pathExtension.lowercased()
        let saved = CharacterFileSelection(filename: UUID().uuidString + "." + ext, originalName: (originalName as NSString).lastPathComponent)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(saved.filename)
        try data.write(to: destination, options: .atomic)
        do { try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("selection.json"), options: .atomic) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        if let old { try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.filename)) }
        return saved
    }
}
