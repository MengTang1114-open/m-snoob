import AppKit
import ServiceManagement

protocol RestSnowControls: AnyObject {
    var snowfall: Snowfall { get }
    var accumulates: Bool { get }
    var thaws: Bool { get }
    var snowOnWindows: Bool { get }
    var behindWindows: Bool { get }
    var showsInScreenshots: Bool { get }
    var opensAtLogin: Bool { get }
    func setSnowfall(_ value: Snowfall)
    func setAccumulates(_ on: Bool)
    func setThaws(_ on: Bool)
    func setSnowOnWindows(_ on: Bool)
    func setBehindWindows(_ on: Bool)
    func setShowsInScreenshots(_ on: Bool)
    func setOpensAtLogin(_ on: Bool)
    func clearSnow()
}

/// Timer, where the ghost comes up, the click catcher, and the little ghost that stays on the desktop.
final class ReminderController {
    let clock = RestClock()
    private let hit = GhostHitWindow()
    private let floater = FloaterWindow()
    private let undo = UndoWindow()
    private let panel: RestPopover
    private var timer: Timer?
    var screens: () -> [ScreenSnow] = { [] }
    var statusButton: () -> NSView? = { nil }

    init(controls: RestSnowControls) {
        panel = RestPopover(clock: clock, controls: controls)
        hit.onClick = { [weak self] in self?.clickedGhost() }
        floater.onTap = { [weak self] in self?.togglePanel(fromFloater: true) }
        floater.onMoved = { [weak self] in self?.saveFloater() }
        floater.onDragBegan = { [weak self] in self?.panel.close() }
        undo.onUndo = { [weak self] in
            self?.clock.undo()
            self?.undo.orderOut(nil)
            self?.refreshChrome()
        }
        panel.onHiddenChanged = { [weak self] in self?.applyFloaterVisibility() }
    }

    func start() {
        placeFloater()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func showPanel() {
        togglePanel(fromFloater: false)
    }

    func screenLocked() { clock.screenLocked(); hit.orderOut(nil) }
    func screenUnlocked() { clock.screenUnlocked() }
    func systemSlept() { clock.systemSlept(); hit.orderOut(nil) }
    func systemWoke() { clock.systemWoke() }

    private func tick() {
        clock.tick()
        clock.noteActivity(idle: idleSeconds())
        clock.ghostBusy = screens().contains { $0.simulation.hasReminder }
        if let due = clock.due(), summon(due) {
            clock.markShown(due.at)
        }
        for snow in screens() {
            snow.setReminderDetail(snow.simulation.hasReminder)
        }
        updateHit()
        refreshChrome()
    }

    private func clickedGhost() {
        var clicked = false
        for snow in screens() where snow.simulation.clickReminder() {
            clicked = true
            break
        }
        if clicked { clock.ghostClicked() }
        hit.orderOut(nil)
        refreshChrome()
    }

    private func summon(_ due: RestClock.Due) -> Bool {
        let hold = Float(Preferences.restHoldSeconds)
        if let front = frontWindow(), let snow = screen(containing: front.appKitCenter) {
            let local = localFrame(of: front.bounds, on: snow.screen)
            let windowTop = snow.screen.frame.minY + local.maxY
            let gap = snow.screen.visibleFrame.maxY - windowTop
            let topOnScreen = local.maxY > 8 && local.minY < snow.screen.frame.height
            let x = Float(local.minX + local.width * 0.75)
            if local.width < 160 || !topOnScreen {
                NSLog("雪噗噗: 退到底部，窗口太窄 width=%.0f gap=%.0f", local.width, gap)
            } else {
                switch snow.simulation.reminderFit(window: front.id, x: x) {
                case .ready(let needed):
                    if gap + 0.5 >= CGFloat(needed),
                       snow.simulation.summonReminder(window: front.id, x: x, caption: due.caption, hold: hold) {
                        return true
                    }
                    if gap + 0.5 < CGFloat(needed) {
                        NSLog("雪噗噗: 退到底部，gap %.0f pt，需要 %.0f pt", gap, needed)
                    } else {
                        NSLog("雪噗噗: 退到底部，那一列被挡住 gap=%.0f 需要=%.0f", gap, needed)
                    }
                case .blocked(let reason):
                    NSLog("雪噗噗: 退到底部，\(reason) gap=%.0f", gap)
                }
            }
            if summonOnGround(of: snow, caption: due.caption, hold: hold) { return true }
        }
        guard let snow = screens().first else { return false }
        NSLog("雪噗噗: 退到底部，没有可用的窗口")
        return summonOnGround(of: snow, caption: due.caption, hold: hold)
    }

    private func summonOnGround(of snow: ScreenSnow, caption: String, hold: Float) -> Bool {
        let visible = snow.screen.visibleFrame
        var x = visible.maxX - snow.screen.frame.minX - 120
        if !Preferences.floaterHidden, snow.screen.frame.intersects(floater.frame) {
            x = min(x, floater.frame.midX - snow.screen.frame.minX - 100)
        }
        x = max(x, 70)
        return snow.simulation.summonReminder(window: nil, x: Float(x), caption: caption, hold: hold)
    }

    private func updateHit() {
        var frame: CGRect?
        for snow in screens() {
            if let found = snow.reminderGlobalFrame() {
                frame = found
                break
            }
        }
        guard let frame else {
            if hit.isVisible { hit.orderOut(nil) }
            return
        }
        hit.setFrame(frame, display: true)
        if !hit.isVisible { hit.orderFrontRegardless() }
    }

    private func refreshChrome() {
        let pastFirst = clock.running && clock.elapsed >= Preferences.restFirstMinutes * 60
        let mood: GhostMood = !clock.running ? .dozing : pastFirst ? .anxious : .timing
        floater.update(
            caption: RestClock.clockText(clock.running ? clock.elapsed : 0),
            mood: mood,
            urgent: pastFirst
        )
        if clock.canUndo, !Preferences.floaterHidden, floater.isVisible {
            let frame = floater.frame
            undo.setFrameOrigin(CGPoint(x: frame.minX - undo.frame.width - 6, y: frame.midY - undo.frame.height / 2))
            if !undo.isVisible { undo.orderFrontRegardless() }
        } else if undo.isVisible {
            undo.orderOut(nil)
        }
        if panel.isShown { panel.refresh() }
    }

    private func togglePanel(fromFloater: Bool) {
        guard let view = fromFloater ? floater.anchorView : statusButton() else { return }
        panel.toggle(from: view, edge: fromFloater ? .maxY : .minY)
    }

    private func placeFloater() {
        let size = floater.frame.size
        if let saved = Preferences.floaterOrigin, NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -40, dy: -40).contains(saved) }) {
            floater.setFrameOrigin(saved)
        } else {
            floater.setFrameOrigin(defaultOrigin(size: size))
        }
        applyFloaterVisibility()
    }

    private func saveFloater() {
        Preferences.floaterOrigin = floater.frame.origin
    }

    private func applyFloaterVisibility() {
        if Preferences.floaterHidden {
            floater.orderOut(nil)
            undo.orderOut(nil)
        } else if !floater.isVisible {
            floater.orderFrontRegardless()
        }
    }

    private func defaultOrigin(size: CGSize) -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return CGPoint(x: visible.maxX - size.width - 16, y: visible.minY + 16)
    }

    private func idleSeconds() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 999
    }

    private struct FrontWindow {
        var id: CGWindowID
        var bounds: CGRect
        var appKitCenter: CGPoint {
            let primary = NSScreen.screens.first?.frame.height ?? 0
            return CGPoint(x: bounds.midX, y: primary - bounds.midY)
        }
    }

    private func frontWindow() -> FrontWindow? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let own = ProcessInfo.processInfo.processIdentifier
        let skip: Set<String> = ["Dock", "Window Server", "WindowManager"]
        for entry in list {
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32, pid != own,
                  let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let info = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: info),
                  bounds.width >= 160, bounds.height >= 80,
                  let alpha = entry[kCGWindowAlpha as String] as? Double, alpha > 0.4,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID, id != 0
            else { continue }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if skip.contains(owner) { continue }
            return FrontWindow(id: id, bounds: bounds)
        }
        return nil
    }

    private func screen(containing point: CGPoint) -> ScreenSnow? {
        screens().first { $0.screen.frame.contains(point) }
    }

    /// Window-list bounds are top-left of the primary display. Overlay coordinates are bottom-left of `screen`.
    private func localFrame(of bounds: CGRect, on screen: NSScreen) -> CGRect {
        let primary = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgScreen = CGRect(x: screen.frame.minX, y: primary - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        return CGRect(x: bounds.minX - cgScreen.minX, y: cgScreen.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
    }
}

// MARK: - Click catcher

final class GhostHitWindow: NSWindow {
    var onClick: () -> Void = {}

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = GhostHitView()
        view.onClick = { [weak self] in self?.onClick() }
        contentView = view
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        FixedSpace.hold(self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class GhostHitView: NSView {
    var onClick: () -> Void = {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
}

// MARK: - Floating ghost

final class FloaterWindow: NSPanel {
    var onTap: () -> Void = {}
    var onMoved: () -> Void = {}
    /// A drag is starting. The panel closes here instead of trying to follow the window.
    var onDragBegan: () -> Void = {}
    private let body = FloaterBody()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 118),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = body
    }

    var anchorView: NSView { body }

    func update(caption: String, mood: GhostMood, urgent: Bool) {
        body.caption.stringValue = caption
        body.caption.textColor = urgent ? .systemRed : .labelColor
        body.portrait.mood = mood
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        FixedSpace.hold(self)
    }

    /// A popover only shows from a window that can become key. This panel stays nonactivating, so that does not pull the app forward.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {}
}

/// Clicks land here, including on the Metal view, so a drag moves the whole ghost.
private final class FloaterBody: NSView {
    let portrait: GhostPortraitView
    let caption = NSTextField(labelWithString: "0:00")
    private let capsule = NSView()

    init() {
        portrait = GhostPortraitView(portrait: GhostPortraitRenderer())
        super.init(frame: NSRect(x: 0, y: 0, width: 96, height: 118))
        portrait.translatesAutoresizingMaskIntoConstraints = false
        capsule.wantsLayer = true
        capsule.layer?.cornerRadius = 9
        capsule.translatesAutoresizingMaskIntoConstraints = false
        caption.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        caption.alignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(portrait)
        addSubview(capsule)
        addSubview(caption)
        NSLayoutConstraint.activate([
            portrait.leadingAnchor.constraint(equalTo: leadingAnchor),
            portrait.trailingAnchor.constraint(equalTo: trailingAnchor),
            portrait.topAnchor.constraint(equalTo: topAnchor),
            portrait.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -26),
            capsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            capsule.heightAnchor.constraint(equalToConstant: 20),
            capsule.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            caption.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 8),
            caption.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -8),
            caption.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])
        paintCapsule()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintCapsule()
    }

    private func paintCapsule() {
        capsule.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? FloaterWindow else { return }
        let startLocation = NSEvent.mouseLocation
        let startOrigin = panel.frame.origin
        var dragged = false
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let now = NSEvent.mouseLocation
            if hypot(now.x - startLocation.x, now.y - startLocation.y) > 3 {
                if !dragged { panel.onDragBegan() }
                dragged = true
            }
            panel.setFrameOrigin(CGPoint(x: startOrigin.x + now.x - startLocation.x, y: startOrigin.y + now.y - startLocation.y))
        }
        if dragged { panel.onMoved() } else { panel.onTap() }
    }
}

// MARK: - Undo

final class UndoWindow: NSPanel {
    var onUndo: () -> Void = {}

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 156, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = NSColor(white: 0.1, alpha: 0.92)
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let button = NSButton(title: "误触了，接着计时", target: self, action: #selector(undo))
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .white
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.frame = NSRect(x: 0, y: 0, width: 156, height: 28)
        contentView?.addSubview(button)
    }

    @objc private func undo() { onUndo() }
}
