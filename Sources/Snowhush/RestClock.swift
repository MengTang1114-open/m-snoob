import AppKit

/// One stretch of computer use. Input starts it. Lock, sleep, or a click on the ghost ends it.
final class RestClock {
    private(set) var elapsed: TimeInterval = 0
    private var started: Date?
    private var lastMilestone: TimeInterval = 0
    private var screenIsLocked = false
    private var systemIsAsleep = false
    private var pausedUntil: Date?
    private var undoSnapshot: Snapshot?
    private var undoUntil = Date.distantPast

    var ghostBusy = false

    struct Due {
        var caption: String
        var at: TimeInterval
    }

    private struct Snapshot {
        var spent: TimeInterval
        var milestone: TimeInterval
    }

    var running: Bool { started != nil }
    var today: TimeInterval { Preferences.restToday }
    var canUndo: Bool { undoSnapshot != nil && Date() < undoUntil }
    var paused: Bool { pausedUntil.map { $0 > Date() } ?? false }

    /// Clock time the paused reminders come back, for the panel line 「xx:xx 恢复」.
    var pauseResumeText: String? {
        guard let pausedUntil, pausedUntil > Date() else { return nil }
        return Self.hourMinute.string(from: pausedUntil)
    }

    func endPause() { pausedUntil = nil }

    private static let hourMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func tick() {
        rollToday()
        guard let started, !blocked else { return }
        elapsed = Date().timeIntervalSince(started)
    }

    /// The milestone to raise a sign for, if one is due and no ghost is already up.
    func due() -> Due? {
        guard started != nil, !blocked, !paused, !ghostBusy else { return nil }
        let first = Preferences.restFirstMinutes * 60
        let step = max(Preferences.restIntervalMinutes * 60, 1)
        guard elapsed + 0.05 >= first else { return nil }
        let index = floor((elapsed - first) / step)
        let at = first + max(index, 0) * step
        guard at > lastMilestone + 0.4 else { return nil }
        return Due(caption: Self.caption(at), at: at)
    }

    func markShown(_ at: TimeInterval) {
        lastMilestone = at
    }

    func noteActivity(idle: TimeInterval) {
        guard started == nil, !blocked, idle < 0.6 else { return }
        begin()
    }

    func screenLocked() {
        screenIsLocked = true
        endRound(startAnother: false)
    }

    func screenUnlocked() {
        screenIsLocked = false
    }

    func systemSlept() {
        systemIsAsleep = true
        endRound(startAnother: false)
    }

    func systemWoke() {
        systemIsAsleep = false
    }

    /// The ghost was clicked. The round ends and a new one starts at once.
    func ghostClicked() {
        endRound(startAnother: true)
    }

    func undo() {
        guard let snapshot = undoSnapshot, Date() < undoUntil else { return }
        Preferences.restToday = max(0, Preferences.restToday - snapshot.spent)
        started = Date().addingTimeInterval(-snapshot.spent)
        elapsed = snapshot.spent
        lastMilestone = snapshot.milestone
        undoSnapshot = nil
    }

    func pauseOneHour() {
        pausedUntil = Date().addingTimeInterval(60 * 60)
    }

    /// Quit counts the unfinished round toward today, then stops.
    func stop() {
        endRound(startAnother: false)
    }

    static func caption(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(max(minutes, 0))min"
    }

    static func clockText(_ seconds: TimeInterval) -> String {
        let whole = max(Int(seconds), 0)
        if whole >= 3600 {
            return String(format: "%d:%02d:%02d", whole / 3600, (whole / 60) % 60, whole % 60)
        }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    static func todayText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分"
    }

    private var blocked: Bool { screenIsLocked || systemIsAsleep }

    private func begin() {
        started = Date()
        elapsed = 0
        lastMilestone = 0
        undoSnapshot = nil
    }

    private func endRound(startAnother: Bool) {
        guard let started else {
            if !startAnother { self.started = nil }
            return
        }
        let spent = Date().timeIntervalSince(started)
        let previousToday = Preferences.restToday
        Preferences.restToday = previousToday + spent
        if startAnother {
            undoSnapshot = Snapshot(spent: spent, milestone: lastMilestone)
            undoUntil = Date().addingTimeInterval(10)
            self.started = Date()
            elapsed = 0
            lastMilestone = 0
        } else {
            undoSnapshot = nil
            self.started = nil
            elapsed = 0
            lastMilestone = 0
        }
    }

    private func rollToday() {
        let bucket = Self.bucket(Date())
        guard Preferences.restBucket != bucket else { return }
        Preferences.restBucket = bucket
        Preferences.restToday = 0
    }

    /// The day rolls over at 04:00 local time.
    static func bucket(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let day = hour < 4 ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
