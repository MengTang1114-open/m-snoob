import AppKit
import MetalKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, RestSnowControls {
    private var device: MTLDevice!
    private var screens: [ScreenSnow] = []
    var snowfall = Snowfall.steady
    var accumulates = true
    var thaws = true
    var snowOnWindows = true
    var behindWindows = false
    private var snowfallHeld = false
    private var statusItem: NSStatusItem!
    private var observers: [NSObjectProtocol] = []
    private var screensAsleep = false
    private var screenLocked = false
    private var sessionInactive = false
    private var welcome: WelcomeController?
    private let power = PowerMonitor()
    private var reminder: ReminderController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.moveIfNeeded() {
            NSApp.terminate(nil)
            return
        }
        Preferences.registerDefaults()
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSApp.terminate(nil)
            return
        }
        self.device = device
        snowfall = Preferences.snowfall
        accumulates = Preferences.accumulate
        thaws = Preferences.meltSnow
        snowOnWindows = Preferences.snowOnWindows
        behindWindows = Preferences.behindWindows
        snowfallHeld = !Preferences.welcomed
        syncScreens()
        guard !screens.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        statusItem = makeStatusItem()
        updateStatusIcon()
        reminder = ReminderController(controls: self)
        reminder.screens = { [unowned self] in screens }
        reminder.statusButton = { [unowned self] in statusItem.button }
        observeSystem()
        reminder.start()
        if snowfallHeld {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.showWelcome() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        reminder?.clock.stop()
    }

    // MARK: - Displays

    /// One overlay per display: new displays get snow, removed ones lose theirs, the rest follow resolution changes.
    private func syncScreens() {
        let current = NSScreen.screens
        let ids = Set(current.compactMap(\.displayID))
        for gone in screens where !ids.contains(gone.displayID) { gone.close() }
        screens.removeAll { !ids.contains($0.displayID) }

        for screen in current {
            if let existing = screens.first(where: { $0.displayID == screen.displayID }) {
                existing.fit(to: screen)
            } else if let snow = ScreenSnow(screen: screen, device: device, snowOnWindows: { [unowned self] in snowOnWindows }) {
                snow.simulation.snowfallHeld = snowfallHeld
                snow.simulation.snowfallReleased = { [weak self] in self?.releaseSnowfall() }
                snow.apply(power.budget)
                screens.append(snow)
            }
        }
        updateActivity()
    }

    private func releaseSnowfall() {
        snowfallHeld = false
        for snow in screens { snow.simulation.snowfallHeld = false }
    }

    private func showWelcome() {
        let welcome = WelcomeController()
        welcome.scatter = { [weak self] pieces in
            guard let self, let first = pieces.first else { return }
            let point = CGPoint(x: CGFloat(first.position.x), y: CGFloat(first.position.y))
            guard let snow = screens.first(where: { $0.window.frame.contains(point) }) ?? screens.first else { return }
            let origin = SIMD2(Float(snow.window.frame.minX), Float(snow.window.frame.minY))
            snow.simulation.scatter(pieces.map { piece in
                var local = piece
                local.position -= origin
                return local
            })
        }
        welcome.skipped = { [weak self] in self?.releaseSnowfall() }
        welcome.finished = { [weak self] in
            Preferences.welcomed = true
            self?.welcome = nil
        }
        self.welcome = welcome
        welcome.show()
    }

    // MARK: - Menu bar

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "雪噗噗")
        item.button?.target = self
        item.button?.action = #selector(openPanel)
        return item
    }

    @objc private func openPanel() {
        reminder.showPanel()
    }

    var showsInScreenshots: Bool { Preferences.showInScreenshots }
    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setSnowfall(_ value: Snowfall) {
        snowfall = value
        Preferences.snowfall = value
        for snow in screens { snow.simulation.snowfall = value }
        updateStatusIcon()
    }

    func setAccumulates(_ on: Bool) {
        accumulates = on
        Preferences.accumulate = on
        for snow in screens { snow.simulation.accumulates = on }
    }

    func setThaws(_ on: Bool) {
        thaws = on
        Preferences.meltSnow = on
        for snow in screens { snow.simulation.thaws = on }
    }

    func setSnowOnWindows(_ on: Bool) {
        snowOnWindows = on
        Preferences.snowOnWindows = on
        if !on { screens.forEach { $0.dropWindowSnow() } }
    }

    func clearSnow() {
        let direction = screens.first?.simulation.breezeDirection ?? -1
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for snow in screens { snow.simulation.blowAway(direction: direction, calm: calm) }
    }

    func setBehindWindows(_ on: Bool) {
        behindWindows = on
        Preferences.behindWindows = on
        for snow in screens {
            snow.window.behindWindows = on
            if on { snow.dropWindowSnow() }
        }
    }

    func setShowsInScreenshots(_ on: Bool) {
        Preferences.showInScreenshots = on
        for snow in screens {
            snow.window.showsInScreenshots = on
            snow.dock.window.showsInScreenshots = on
        }
    }

    func setOpensAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        guard on != (service.status == .enabled) else { return }
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("Snowhush: login item change failed: \(error)")
        }
    }

    private func updateStatusIcon() {
        statusItem.button?.appearsDisabled = snowfall == .off
    }

    // MARK: - System

    private func observeSystem() {
        power.changed = { [unowned self] in screens.forEach { $0.apply(power.budget) } }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        // Display sleep only pauses the snow. A lock or the whole machine sleeping ends the round.
        observe(workspace, NSWorkspace.willSleepNotification) { $0.reminder.systemSlept() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.reminder.systemWoke() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) {
            $0.screenLocked = true
            $0.reminder.screenLocked()
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
            $0.screenLocked = false
            $0.reminder.screenUnlocked()
        }
        observe(.default, NSWindow.didChangeOcclusionStateNotification) { _ in }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.syncScreens() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.screens.forEach { $0.spaceChanged() } }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.screens.forEach { $0.watchWindows() } }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: AnyObject? = nil,
        _ change: @escaping (AppDelegate) -> Void
    ) {
        observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            guard let self else { return }
            change(self)
            self.updateActivity()
        })
    }

    private func updateActivity() {
        let awake = !screensAsleep && !screenLocked && !sessionInactive
        for snow in screens {
            snow.setActive(awake && snow.window.occlusionState.contains(.visible))
        }
    }
}
