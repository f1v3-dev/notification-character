import AppKit
import ApplicationServices
import NotificationCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: CatPanel!
    private var cat: CatView!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let monitor = DockBadgeMonitor()
    private var monitorRevision = 0
    private var snapshot: BadgeSnapshot?
    private var policy = NotificationPolicy()
    private var paused = false
    private var hidden = false
    private var previewUntil: TimeInterval = 0
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastMouse = NSEvent.mouseLocation
    private var lastMovement = ProcessInfo.processInfo.systemUptime
    private var lastStatusCheck: TimeInterval = -.infinity
    private var lastPresentation = ""
    private var statusDescription = "Dock 배지 확인 중"
    private var observers: [NSObjectProtocol] = []
    private var frames = 0
    private var characterPicker: NSOpenPanel?
    private var characterLoadTask: Task<Void, Never>?
    private lazy var characterFiles = CharacterFileStore(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NotificationCharacter/Characters"))
    private var testing: Bool { CommandLine.arguments.contains("--smoke-test") }
    private lazy var settings: UserDefaults = testing ? UserDefaults(suiteName: "NotificationCharacter.Test.\(UUID().uuidString)")! : .standard
    private let intervals: [TimeInterval] = [0.3, 0.5, 1, 2, 5]
    private var enabledApps: Set<MessengerApp> {
        Set(MessengerApp.allCases.filter { settings.object(forKey: "monitor.\($0.rawValue)") == nil || settings.bool(forKey: "monitor.\($0.rawValue)") })
    }
    private var interval: TimeInterval {
        let saved = settings.double(forKey: "pollInterval")
        return intervals.contains(saved) ? saved : 1
    }
    private var adaptive: Bool { settings.object(forKey: "adaptivePolling") == nil || settings.bool(forKey: "adaptivePolling") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !testing && NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.notification-character.CursorCat").count > 1 {
            NSApp.terminate(nil); return
        }
        let savedSize = settings.double(forKey: "catSize")
        let size: CGFloat = [72.0, 96.0, 120.0].contains(savedSize) ? savedSize : 96
        panel = CatPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        cat = CatView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        cat.autoresizingMask = [.width, .height]; panel.contentView = cat
        cat.removeWhiteBackground = settings.bool(forKey: "removeWhiteBackground")
        if !testing, settings.bool(forKey: "useImportedCharacter"), let url = characterFiles.selectedURL {
            loadCharacter(url: url, copy: false, preview: false)
        }
        policy = NotificationPolicy(mode: AlertMode(rawValue: settings.string(forKey: "alertMode") ?? "") ?? .unread)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "알림 친구")
        statusItem.button?.imagePosition = .imageLeading
        if !testing && CommandLine.arguments.contains("--show-preview") { previewUntil = Date().timeIntervalSince1970 + 10 }
        snapToCursor(); refresh(now: Date().timeIntervalSince1970); scheduleTimer(visible: panel.isVisible)
        if testing { runWindowSmokeTest(); return }
        startMonitoring()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.snapToCursor(); self?.startMonitoring()
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.monitorRevision += 1; self?.monitor.stop(); self?.snapshot = nil
            self?.refresh(now: Date().timeIntervalSince1970)
        })
    }

    private func startMonitoring() {
        monitorRevision += 1
        let revision = monitorRevision
        snapshot = .uniform(.starting); refresh(now: Date().timeIntervalSince1970)
        monitor.start(enabled: enabledApps, interval: interval, adaptive: adaptive) { [weak self] snapshot in
            guard let self, self.monitorRevision == revision else { return }
            self.snapshot = snapshot; self.refresh(now: Date().timeIntervalSince1970)
        }
    }
    private func refresh(now: TimeInterval) {
        policy.update(snapshot, now: now)
        if let snapshot, snapshot.isFresh(at: now) {
            if !snapshot.activeApps.isEmpty { statusDescription = "알림 있음: " + snapshot.activeApps.map(\.rawValue).joined(separator: " · ") }
            else if snapshot.apps.values.contains(where: { $0.status == .permission }) { statusDescription = "손쉬운 사용 권한이 필요합니다" }
            else if snapshot.apps.values.contains(where: { [.query, .starting].contains($0.status) }) { statusDescription = "Dock 배지 확인 중 · 다시 감지할 수 있어요" }
            else { statusDescription = "알림 대기 중" }
        } else { statusDescription = "Dock 감지 응답 대기 중" }
        present(now: now)
    }
    private func present(now: TimeInterval) {
        let show = !hidden && (policy.visible || now < previewUntil)
        if show && !panel.isVisible { snapToCursor(); panel.orderFrontRegardless(); scheduleTimer(visible: true) }
        else if !show && panel.isVisible { panel.orderOut(nil); scheduleTimer(visible: false) }
        cat.hasNotification = policy.visible
        cat.isPlaybackActive = show
        statusItem.button?.toolTip = "알림 친구 — \(statusDescription)"
        let signature = "\(show)|\(policy.mode.rawValue)|\(statusDescription)|\(String(describing: snapshot?.apps))|\(policy.displayedApps)"
        if signature != lastPresentation { lastPresentation = signature; updateMenuBar(); rebuildMenu() }
    }
    private func scheduleTimer(visible: Bool) {
        timer?.invalidate()
        let timer = Timer(timeInterval: visible ? 1 / 60 : 0.25, target: self, selector: #selector(update), userInfo: nil, repeats: true)
        timer.tolerance = visible ? 0.004 : 0.03
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    private func destination() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        return FollowGeometry.target(mouse: mouse, size: panel.frame.size, screen: screen?.visibleFrame ?? NSRect(x: mouse.x - 400, y: mouse.y - 300, width: 800, height: 600))
    }
    private func snapToCursor() { panel.setFrameOrigin(destination()); lastTick = ProcessInfo.processInfo.systemUptime; lastMouse = NSEvent.mouseLocation }
    @objc private func update() {
        frames += 1
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTick; lastTick = now
        if now - lastStatusCheck >= 0.25 { lastStatusCheck = now; refresh(now: Date().timeIntervalSince1970) }
        guard panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        if hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 1 { lastMovement = now }
        lastMouse = mouse
        if !paused {
            let target = destination(), origin = panel.frame.origin
            let distance = hypot(target.x - origin.x, target.y - origin.y)
            panel.setFrameOrigin(distance > 800 ? target : FollowGeometry.step(from: origin, to: target, dt: dt))
            cat.look = max(-1.5, min(1.5, (target.x - origin.x) / 40))
            cat.moving = distance > 6 || now - lastMovement < 0.15
        } else { cat.moving = false }
        cat.advanceMedia(dt: dt); cat.phase += min(dt, 0.1); cat.needsDisplay = true
    }
    private func updateMenuBar() {
        let text = NSMutableAttributedString(string: "")
        if !settings.bool(forKey: "hideMenuBadges") {
            let counts = settings.bool(forKey: "showCounts")
            for app in MessengerApp.allCases where enabledApps.contains(app) {
                let record = snapshot?.isFresh(at: Date().timeIntervalSince1970) == true ? snapshot?.apps[app] : nil
                let color: NSColor = record?.hasBadge == true ? .systemRed : record?.status == .zero ? .secondaryLabelColor : .systemOrange
                let mark = record?.hasBadge == true ? (counts && record?.status == .count ? record!.value : "•") : record?.status == .zero ? (counts ? "0" : "•") : "?"
                let label = app == .slack ? "S" : app == .line ? "L" : "W"
                text.append(NSAttributedString(string: "  \(label) \(mark)", attributes: [.foregroundColor: color, .font: NSFont.menuBarFont(ofSize: 12)]))
            }
        }
        statusItem.button?.attributedTitle = text
    }
    private func item(_ title: String, _ action: Selector? = nil, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; return entry
    }
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(item("알림 친구")); menu.addItem(item(statusDescription)); menu.addItem(.separator())
        for (index, app) in MessengerApp.allCases.enumerated() {
            let record = snapshot?.apps[app]
            let status: String
            switch record?.status {
            case .count: status = "배지 \(record!.value)"
            case .symbol: status = "배지 있음"
            case .zero: status = "배지 없음"
            case .missing: status = "Dock에 앱 없음"
            case .disabled: status = "감지 꺼짐"
            case .permission: status = "권한 필요"
            default: status = "확인 중"
            }
            let row = item("\(app.rawValue): \(status)", #selector(openMessenger(_:))); row.tag = index; menu.addItem(row)
        }
        let selection = item("감지할 앱"), selectionMenu = NSMenu()
        for (index, app) in MessengerApp.allCases.enumerated() {
            let entry = item(app.rawValue, #selector(toggleApp(_:))); entry.tag = index
            entry.state = enabledApps.contains(app) ? .on : .off; selectionMenu.addItem(entry)
        }
        selection.submenu = selectionMenu; menu.addItem(selection); menu.addItem(.separator())
        let modes = item("알림이 오면 언제까지 보일까요?"), modeMenu = NSMenu()
        for (index, mode) in AlertMode.allCases.enumerated() {
            let entry = item(mode.title, #selector(changeMode(_:))); entry.tag = index
            entry.state = policy.mode == mode ? .on : .off; modeMenu.addItem(entry)
        }
        modes.submenu = modeMenu; menu.addItem(modes)
        menu.addItem(item("이번 알림 닫기", #selector(dismissNotification)))
        menu.addItem(item("10초 미리보기", #selector(preview)))
        menu.addItem(item(paused ? "다시 따라오기" : "여기서 쉬기", #selector(togglePause)))
        menu.addItem(item(hidden ? "알림 캐릭터 켜기" : "알림 캐릭터 끄기", #selector(toggleHidden)))
        let character = item("캐릭터 파일"), characterMenu = NSMenu()
        let currentName = cat.characterImage == nil ? "기본 고양이" : characterFiles.selection?.originalName ?? "내 캐릭터"
        characterMenu.addItem(item("현재: " + currentName)); characterMenu.addItem(.separator())
        characterMenu.addItem(item("이미지 / GIF / 동영상 불러오기…", #selector(importCharacter)))
        let restore = item("기본 고양이 사용", #selector(useDefaultCharacter)); restore.state = cat.characterImage == nil ? .on : .off
        characterMenu.addItem(restore)
        if characterFiles.selection != nil { characterMenu.addItem(item("마지막에 불러온 캐릭터 사용", #selector(useImportedCharacter))) }
        characterMenu.addItem(.separator())
        let cutout = item("MP4·MOV 흰 배경 제거", #selector(toggleWhiteBackground))
        cutout.state = cat.removeWhiteBackground ? .on : .off; characterMenu.addItem(cutout)
        character.submenu = characterMenu; menu.addItem(character)
        let sizeItem = item("캐릭터 크기"), sizes = NSMenu()
        for (label, value) in [("작게", 72), ("보통", 96), ("크게", 120)] {
            let entry = item(label, #selector(changeSize(_:))); entry.tag = value
            entry.state = Int(panel.frame.width) == value ? .on : .off; sizes.addItem(entry)
        }
        sizeItem.submenu = sizes; menu.addItem(sizeItem)
        let timing = item("감시 간격"), timingMenu = NSMenu()
        for (index, value) in intervals.enumerated() {
            let entry = item("\(value)초", #selector(changeInterval(_:))); entry.tag = index
            entry.state = interval == value ? .on : .off; timingMenu.addItem(entry)
        }
        let idle = item("변화 없으면 최대 10초까지 늘리기", #selector(toggleAdaptive)); idle.state = adaptive ? .on : .off
        timingMenu.addItem(.separator()); timingMenu.addItem(idle); timing.submenu = timingMenu; menu.addItem(timing)
        let badges = item("메뉴바에 배지 표시", #selector(toggleMenuBadges)); badges.state = settings.bool(forKey: "hideMenuBadges") ? .off : .on; menu.addItem(badges)
        let counts = item("메뉴바 배지를 숫자로 표시", #selector(toggleCounts)); counts.state = settings.bool(forKey: "showCounts") ? .on : .off; menu.addItem(counts)
        menu.addItem(.separator()); menu.addItem(item("다시 감지", #selector(rescan)))
        menu.addItem(item("손쉬운 사용 권한 설정…", #selector(requestAccessibility)))
        menu.addItem(.separator()); menu.addItem(item("알림 친구 종료", #selector(quit), key: "q"))
        statusItem.menu = menu
    }
    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard MessengerApp.allCases.indices.contains(sender.tag) else { return }
        let app = MessengerApp.allCases[sender.tag]
        settings.set(!enabledApps.contains(app), forKey: "monitor.\(app.rawValue)"); startMonitoring()
    }
    @objc private func openMessenger(_ sender: NSMenuItem) {
        guard MessengerApp.allCases.indices.contains(sender.tag), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MessengerApp.allCases[sender.tag].bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func changeMode(_ sender: NSMenuItem) {
        guard AlertMode.allCases.indices.contains(sender.tag) else { return }
        let mode = AlertMode.allCases[sender.tag]
        policy.select(mode, snapshot: snapshot, now: Date().timeIntervalSince1970)
        settings.set(mode.rawValue, forKey: "alertMode"); present(now: Date().timeIntervalSince1970); rebuildMenu()
    }
    @objc private func dismissNotification() { policy.dismiss(); previewUntil = 0; present(now: Date().timeIntervalSince1970) }
    @objc private func preview() { hidden = false; previewUntil = Date().timeIntervalSince1970 + 10; present(now: Date().timeIntervalSince1970); rebuildMenu() }
    @objc private func togglePause() { paused.toggle(); rebuildMenu() }
    @objc private func toggleHidden() { hidden.toggle(); present(now: Date().timeIntervalSince1970); rebuildMenu() }
    @objc private func changeSize(_ sender: NSMenuItem) {
        panel.setContentSize(NSSize(width: sender.tag, height: sender.tag)); settings.set(sender.tag, forKey: "catSize"); snapToCursor(); rebuildMenu()
    }
    @objc private func importCharacter() {
        guard characterPicker == nil else { characterPicker?.makeKeyAndOrderFront(nil); return }
        let picker = NSOpenPanel()
        picker.title = "알림 캐릭터 불러오기"; picker.prompt = "캐릭터로 사용"
        picker.message = "SVG·PNG·JPG·GIF 또는 60초 이하 MP4·MOV를 선택해 주세요. 움직이는 파일은 소리 없이 반복 재생합니다."
        picker.allowedContentTypes = [.svg, .png, .jpeg, .gif, .mpeg4Movie, .quickTimeMovie]; picker.allowsMultipleSelection = false; picker.canChooseDirectories = false
        characterPicker = picker; NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            guard let self else { return }
            defer { self.characterPicker = nil }
            guard response == .OK, let url = picker.url else { return }
            self.loadCharacter(url: url, copy: true, preview: true)
        }
    }
    @objc private func useDefaultCharacter() {
        characterLoadTask?.cancel()
        cat.setMedia(image: nil); settings.set(false, forKey: "useImportedCharacter"); preview(); rebuildMenu()
    }
    @objc private func useImportedCharacter() {
        guard let url = characterFiles.selectedURL else { return }
        loadCharacter(url: url, copy: false, preview: true)
    }
    private func loadCharacter(url: URL, copy: Bool, preview showPreview: Bool) {
        characterLoadTask?.cancel()
        characterLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let media = try await CharacterMedia.readMedia(from: url)
                guard !Task.isCancelled else { return }
                if copy { try characterFiles.save(media.data, originalName: url.lastPathComponent) }
                let playbackURL = copy ? characterFiles.selectedURL : url
                cat.setMedia(image: media.image, videoURL: media.videoURL == nil ? nil : playbackURL, transform: media.transform)
                settings.set(true, forKey: "useImportedCharacter")
                if showPreview { preview() }
                rebuildMenu()
            } catch {
                if !Task.isCancelled && showPreview { showCharacterError(error) }
            }
        }
    }
    private func showCharacterError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "캐릭터를 불러올 수 없습니다"
        alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc private func toggleWhiteBackground() {
        cat.removeWhiteBackground.toggle(); settings.set(cat.removeWhiteBackground, forKey: "removeWhiteBackground")
        preview(); rebuildMenu()
    }
    @objc private func changeInterval(_ sender: NSMenuItem) {
        guard intervals.indices.contains(sender.tag) else { return }
        settings.set(intervals[sender.tag], forKey: "pollInterval"); startMonitoring()
    }
    @objc private func toggleAdaptive() { settings.set(!adaptive, forKey: "adaptivePolling"); startMonitoring() }
    @objc private func toggleMenuBadges() { settings.set(!settings.bool(forKey: "hideMenuBadges"), forKey: "hideMenuBadges"); updateMenuBar(); rebuildMenu() }
    @objc private func toggleCounts() { settings.set(!settings.bool(forKey: "showCounts"), forKey: "showCounts"); updateMenuBar(); rebuildMenu() }
    @objc private func rescan() { startMonitoring() }
    @objc private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        startMonitoring()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        characterLoadTask?.cancel(); cat.isPlaybackActive = false
        monitor.stop(); timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func runWindowSmokeTest() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [self] _ in
            let now = Date().timeIntervalSince1970
            func feed(_ status: BadgeStatus, now: TimeInterval) {
                var records = Dictionary(uniqueKeysWithValues: MessengerApp.allCases.map { ($0, BadgeRecord(.zero)) })
                records[.slack] = BadgeRecord(status, value: status == .count ? "1" : "")
                snapshot = BadgeSnapshot(updatedAt: now, apps: records); refresh(now: now)
            }
            for mode in AlertMode.allCases {
                policy = NotificationPolicy(mode: mode)
                feed(.zero, now: now); precondition(!panel.isVisible)
                feed(.count, now: now); precondition(panel.isVisible)
                precondition(panel.ignoresMouseEvents && !panel.isOpaque && !panel.canBecomeKey)
                feed(.zero, now: now + 1); precondition(panel.isVisible == (mode != .unread))
                if mode == .timed { feed(.zero, now: now + 11); precondition(!panel.isVisible) }
                policy.dismiss(); present(now: now + 11); precondition(!panel.isVisible)
            }
            previewUntil = Date().timeIntervalSince1970 + 2; present(now: Date().timeIntervalSince1970)
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [self] _ in
                precondition(frames > 10 && panel.isVisible)
                print("PASS: native window show/hide in all three modes, click-through, nonactivating, \(frames) animation frames")
                fflush(stdout); NSApp.terminate(nil)
            }
        }
    }
}
