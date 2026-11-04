import AppKit
import NotificationCore

if CommandLine.arguments.contains("--inspect-dock") {
    let records = DockBadgeReader().read(enabled: Set(MessengerApp.allCases))
    let data = try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: records.map { ($0.key.rawValue, $0.value) }))
    print(String(data: data, encoding: .utf8)!)
} else if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > index + 1 {
    let view = CatView(frame: NSRect(x: 0, y: 0, width: 448, height: 448))
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}
