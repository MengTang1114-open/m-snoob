import AppKit
import CoreText

/// The settings popover. One panel for the floater and the menu-bar snowflake.
final class RestPopover: NSObject, NSPopoverDelegate {
    var onHiddenChanged: () -> Void = {}
    private let popover = NSPopover()
    private let controller: RestPanelController
    private var closedAt = Date.distantPast

    init(clock: RestClock, controls: RestSnowControls) {
        controller = RestPanelController(clock: clock, controls: controls)
        super.init()
        controller.onHiddenChanged = { [weak self] in self?.onHiddenChanged() }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
    }

    var isShown: Bool { popover.isShown }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    func refresh() { controller.refresh() }

    /// Clicking the anchor of a transient popover closes it before this runs, so that click does not open it again.
    func toggle(from view: NSView, edge: NSRectEdge) {
        if popover.isShown {
            close()
            return
        }
        if Date().timeIntervalSince(closedAt) < 0.2 { return }
        controller.sync()
        controller.refresh()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
    }

    func popoverDidClose(_ notification: Notification) {
        closedAt = Date()
    }
}

private final class PanelBackdrop: NSVisualEffectView {
    var onAppearance: () -> Void = {}
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearance()
    }
}

private final class RestPanelController: NSViewController {
    var onHiddenChanged: () -> Void = {}
    private let clock: RestClock
    private weak var controls: RestSnowControls?

    private let kicker = NSTextField(labelWithString: "本轮")
    private let bigTime = NSTextField(labelWithString: "0:00")
    private let todayLabel = NSTextField(labelWithString: "今日 0 分钟")
    private let hint = NSTextField(wrappingLabelWithString: "25 分钟时提醒你休息")
    private let pauseButton = NSButton(title: "暂停 1 小时", target: nil, action: nil)
    private let snowfallControl = SnowfallSlider()
    private let accumulateSwitch = NSSwitch()
    private let meltSwitch = NSSwitch()
    private let windowsSwitch = NSSwitch()
    private let behindSwitch = NSSwitch()
    private let shotSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let showSwitch = NSSwitch()
    private let firstStepper = NSStepper()
    private let intervalStepper = NSStepper()
    private let holdStepper = NSStepper()
    private let firstValue = NSTextField(labelWithString: "25 分钟")
    private let intervalValue = NSTextField(labelWithString: "5 分钟")
    private let holdValue = NSTextField(labelWithString: "60 秒")
    private var cards: [NSView] = []

    init(clock: RestClock, controls: RestSnowControls) {
        self.clock = clock
        self.controls = controls
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let effect = PanelBackdrop()
        effect.onAppearance = { [weak self] in self?.repaintCards() }
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.frame = NSRect(x: 0, y: 0, width: 300, height: 640)
        view = effect

        style(kicker, size: 12, color: .secondaryLabelColor, weight: .medium)
        bigTime.font = Self.roundedDigits(34, weight: .medium)
        bigTime.textColor = .labelColor
        todayLabel.font = Self.roundedDigits(20, weight: .medium)
        todayLabel.textColor = .labelColor
        style(hint, size: 12, color: .secondaryLabelColor, weight: .regular)
        hint.preferredMaxLayoutWidth = 168
        pauseButton.bezelStyle = .rounded
        pauseButton.controlSize = .small
        pauseButton.target = self
        pauseButton.action = #selector(pause)

        let hintRow = NSStackView(views: [hint, pauseButton])
        hintRow.orientation = .horizontal
        hintRow.alignment = .centerY
        hintRow.spacing = 8
        pauseButton.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView(views: [kicker, bigTime, todayLabel, hintRow])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2
        header.setCustomSpacing(6, after: todayLabel)

        wire(accumulateSwitch, #selector(accumulateChanged))
        wire(meltSwitch, #selector(meltChanged))
        wire(windowsSwitch, #selector(windowsChanged))
        wire(behindSwitch, #selector(behindChanged))
        wire(shotSwitch, #selector(shotsChanged))
        wire(loginSwitch, #selector(loginChanged))
        wire(showSwitch, #selector(showChanged))
        snowfallControl.changed = { [weak self] value in self?.controls?.setSnowfall(value) }
        configure(firstStepper, min: 1, max: 180, action: #selector(firstChanged))
        configure(intervalStepper, min: 1, max: 60, action: #selector(intervalChanged))
        configure(holdStepper, min: 5, max: 180, action: #selector(holdChanged))

        let clear = NSButton(title: "清除积雪", target: self, action: #selector(clearSnow))
        clear.bezelStyle = .rounded
        clear.controlSize = .small

        let snowCard = card("下雪", rows: [
            fieldLabel("雪量"),
            snowfallControl,
            row("积雪", accumulateSwitch),
            row("融雪", meltSwitch),
            row("窗口顶上积雪", windowsSwitch),
            row("雪落在窗口后面", behindSwitch),
            row("截图里能看到雪", shotSwitch),
            clear,
        ])
        let restCard = card("休息提醒", rows: [
            stepperRow("第一次提醒", firstStepper, firstValue),
            stepperRow("之后每隔", intervalStepper, intervalValue),
            stepperRow("举牌多久", holdStepper, holdValue),
        ])
        let generalCard = card("通用", rows: [
            row("开机时启动", loginSwitch),
            row("显示悬浮小雪怪", showSwitch),
        ])

        let credit = NSTextField(labelWithString: "基于 Snowhush · MIT")
        style(credit, size: 11, color: .secondaryLabelColor, weight: .regular)
        let quit = NSButton(title: "退出雪噗噗", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        let footer = NSStackView(views: [credit, quit])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        quit.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [header, snowCard, restCard, generalCard, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12),
            snowCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            restCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            generalCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            snowfallControl.widthAnchor.constraint(equalTo: snowCard.widthAnchor, constant: -20),
        ])
        effect.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 24
        preferredContentSize = NSSize(width: 300, height: max(height, 420))
        effect.frame.size = preferredContentSize
    }

    private func repaintCards() {
        let appearance = view.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let fill = NSColor.quaternarySystemFill.cgColor
            for card in cards { card.layer?.backgroundColor = fill }
        }
    }

    func sync() {
        guard let controls else { return }
        snowfallControl.snowfall = controls.snowfall
        accumulateSwitch.state = controls.accumulates ? .on : .off
        meltSwitch.state = controls.thaws ? .on : .off
        meltSwitch.isEnabled = controls.accumulates
        windowsSwitch.state = controls.snowOnWindows ? .on : .off
        windowsSwitch.isEnabled = !controls.behindWindows
        behindSwitch.state = controls.behindWindows ? .on : .off
        shotSwitch.state = controls.showsInScreenshots ? .on : .off
        loginSwitch.state = controls.opensAtLogin ? .on : .off
        showSwitch.state = Preferences.floaterHidden ? .off : .on
        firstStepper.doubleValue = Preferences.restFirstMinutes
        intervalStepper.doubleValue = Preferences.restIntervalMinutes
        holdStepper.doubleValue = Preferences.restHoldSeconds
        refreshStepperLabels()
    }

    func refresh() {
        if clock.running {
            kicker.stringValue = "本轮"
            bigTime.stringValue = RestClock.clockText(clock.elapsed)
        } else {
            kicker.stringValue = "还没开始，动一下键盘鼠标就开始"
            bigTime.stringValue = "0:00"
        }
        todayLabel.stringValue = "今日 \(RestClock.todayText(clock.today))"
        if let resume = clock.pauseResumeText {
            hint.stringValue = "提醒已暂停，\(resume) 恢复"
            pauseButton.title = "取消暂停"
        } else {
            hint.stringValue = "\(Int(Preferences.restFirstMinutes)) 分钟时提醒你休息"
            pauseButton.title = "暂停 1 小时"
        }
        bigTime.textColor = clock.running && clock.elapsed >= Preferences.restFirstMinutes * 60 ? .systemRed : .labelColor
    }

    private func refreshStepperLabels() {
        firstValue.stringValue = "\(firstStepper.integerValue) 分钟"
        intervalValue.stringValue = "\(intervalStepper.integerValue) 分钟"
        holdValue.stringValue = "\(holdStepper.integerValue) 秒"
    }

    private func card(_ title: String, rows: [NSView]) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        cards.append(box)
        let heading = NSTextField(labelWithString: title)
        style(heading, size: 12, color: .secondaryLabelColor, weight: .semibold)
        let stack = NSStackView(views: [heading] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        for line in rows where line is NSStackView {
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
        ])
        return box
    }

    private func row(_ name: String, _ control: NSView) -> NSView {
        let label = fieldLabel(name)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let line = NSStackView(views: [label, control])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        return line
    }

    private func stepperRow(_ name: String, _ stepper: NSStepper, _ value: NSTextField) -> NSView {
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        value.alignment = .right
        value.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        let pair = NSStackView(views: [stepper, value])
        pair.orientation = .horizontal
        pair.spacing = 6
        pair.alignment = .centerY
        return row(name, pair)
    }

    private func fieldLabel(_ name: String) -> NSTextField {
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        return label
    }

    private func style(_ label: NSTextField, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
    }

    private func wire(_ toggle: NSSwitch, _ action: Selector) {
        toggle.target = self
        toggle.action = action
        toggle.controlSize = .small
    }

    private func configure(_ stepper: NSStepper, min: Double, max: Double, action: Selector) {
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
    }

    private static func roundedDigits(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        descriptor = descriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    @objc private func pause() {
        if clock.paused { clock.endPause() } else { clock.pauseOneHour() }
        refresh()
    }

    @objc private func accumulateChanged() {
        controls?.setAccumulates(accumulateSwitch.state == .on)
        meltSwitch.isEnabled = accumulateSwitch.state == .on
    }

    @objc private func meltChanged() { controls?.setThaws(meltSwitch.state == .on) }
    @objc private func windowsChanged() { controls?.setSnowOnWindows(windowsSwitch.state == .on) }

    @objc private func behindChanged() {
        controls?.setBehindWindows(behindSwitch.state == .on)
        windowsSwitch.isEnabled = behindSwitch.state != .on
    }

    @objc private func shotsChanged() { controls?.setShowsInScreenshots(shotSwitch.state == .on) }
    @objc private func loginChanged() { controls?.setOpensAtLogin(loginSwitch.state == .on) }

    @objc private func showChanged() {
        Preferences.floaterHidden = showSwitch.state != .on
        onHiddenChanged()
    }

    @objc private func firstChanged() {
        Preferences.restFirstMinutes = firstStepper.doubleValue
        refreshStepperLabels()
        refresh()
    }

    @objc private func intervalChanged() {
        Preferences.restIntervalMinutes = intervalStepper.doubleValue
        refreshStepperLabels()
    }

    @objc private func holdChanged() {
        Preferences.restHoldSeconds = holdStepper.doubleValue
        refreshStepperLabels()
    }

    @objc private func clearSnow() { controls?.clearSnow() }
}
