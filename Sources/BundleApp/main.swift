import Foundation

// Run after `swift build -c release`. This tool bundles and signs; it contains no app logic.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let binary = root.appendingPathComponent(".build/release/NotificationCharacter")
let bundle = root.appendingPathComponent("dist/Notification Character.app")
let contents = bundle.appendingPathComponent("Contents")
let executable = contents.appendingPathComponent("MacOS/NotificationCharacter")
let fileManager = FileManager.default
guard fileManager.isExecutableFile(atPath: binary.path) else {
    fputs("Build first: swift build -c release\n", stderr); exit(1)
}
try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
let staged = executable.deletingLastPathComponent().appendingPathComponent(".NotificationCharacter-\(UUID().uuidString)")
try fileManager.copyItem(at: binary, to: staged)
// POSIX rename replaces the executable without truncating an already-running binary.
guard rename(staged.path, executable.path) == 0 else { perror("rename"); exit(1) }
let plist: [String: Any] = [
    "CFBundleExecutable": "NotificationCharacter",
    "CFBundleIdentifier": "local.notification-character.CursorCat",
    "CFBundleName": "Notification Character",
    "CFBundleDisplayName": "알림 친구",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "2.1.0",
    "CFBundleVersion": "4",
    "LSMinimumSystemVersion": "13.0",
    "LSUIElement": true,
    "NSHighResolutionCapable": true,
]
let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
let sign = Process(); sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
let identity = ProcessInfo.processInfo.environment["CODE_SIGN_IDENTITY"] ?? "-"
sign.arguments = ["--force", "--sign", identity, bundle.path]
try sign.run(); sign.waitUntilExit()
guard sign.terminationStatus == 0 else { exit(sign.terminationStatus) }
print(bundle.path)
let archive = root.appendingPathComponent("dist/Notification-Character.zip")
let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
zip.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", bundle.path, archive.path]
try zip.run(); zip.waitUntilExit()
guard zip.terminationStatus == 0 else { exit(zip.terminationStatus) }
print(archive.path)
