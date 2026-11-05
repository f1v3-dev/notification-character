import AppKit
import NotificationCore

func runMediaCommand(_ action: @escaping @MainActor () async throws -> Void) {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
        do { try await action(); exit(0) }
        catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
    }
    RunLoop.main.run()
}
func argument(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.count > index + 1 else { return nil }
    return CommandLine.arguments[index + 1]
}

if CommandLine.arguments.contains("--inspect-dock") {
    let records = DockBadgeReader().read(enabled: Set(MessengerApp.allCases))
    let data = try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: records.map { ($0.key.rawValue, $0.value) }))
    print(String(data: data, encoding: .utf8)!)
} else if let output = argument(after: "--preview") {
    runMediaCommand {
        let view = CatView(frame: NSRect(x: 0, y: 0, width: 448, height: 448))
        if let source = argument(after: "--character") {
            view.characterImage = try await CharacterMedia.readMedia(from: URL(fileURLWithPath: source)).image
            if CommandLine.arguments.contains("--remove-white-background"), let poster = view.characterImage {
                view.characterImage = WhiteBackgroundRenderer().render(poster: poster)
            }
        }
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    }
} else if let path = argument(after: "--asset-smoke-test") {
    runMediaCommand {
        let input = URL(fileURLWithPath: path)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CharacterImport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CharacterFileStore(directory: folder)
        let file = try await CharacterMedia.readMedia(from: input)
        try store.save(file.data, originalName: input.lastPathComponent)
        let loaded = try await CharacterMedia.readMedia(from: store.selectedURL!)
        precondition(loaded.data == file.data)
        let view = CatView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        view.characterImage = loaded.image
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        precondition((bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 0) > 0)
        view.setMedia(image: nil); view.needsDisplay = true
        view.cacheDisplay(in: view.bounds, to: bitmap)
        print("PASS: native media decode, managed copy, reload, custom rendering, default cat restore")
    }
} else if let path = argument(after: "--media-smoke-test") {
    runMediaCommand { try await MediaSmokeTest.run(video: URL(fileURLWithPath: path)) }
} else if let path = argument(after: "--import-character") {
    runMediaCommand {
        let url = URL(fileURLWithPath: path)
        let media = try await CharacterMedia.readMedia(from: url)
        let store = CharacterFileStore(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NotificationCharacter/Characters"))
        let saved = try store.save(media.data, originalName: url.lastPathComponent)
        UserDefaults.standard.set(true, forKey: "useImportedCharacter")
        if CommandLine.arguments.contains("--remove-white-background") { UserDefaults.standard.set(true, forKey: "removeWhiteBackground") }
        print("Imported: " + saved.originalName)
    }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}
