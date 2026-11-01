import AppKit

enum Snowfall: Int, CaseIterable {
    case off, light, steady, heavy, variable

    var title: String {
        switch self {
        case .off: "不下雪"
        case .light: "小雪"
        case .steady: "中雪"
        case .heavy: "大雪"
        case .variable: "时大时小"
        }
    }

    var flakesPerMegapoint: Float {
        switch self {
        case .off: 0
        case .light: 150
        case .steady: 380
        case .heavy: 800
        case .variable: 380
        }
    }
}

enum Preferences {
    private static let defaults = UserDefaults.standard
    private static let snowfallKey = "snowfall"
    private static let behindWindowsKey = "behindWindows"
    private static let meltSnowKey = "meltSnow"
    private static let accumulateKey = "accumulate"
    private static let snowOnWindowsKey = "snowOnWindows"
    private static let welcomedKey = "welcomed"
    private static let showInScreenshotsKey = "showInScreenshots"
    private static let halloweenKey = "halloween"
    private static let restFirstKey = "restFirstMinutes"
    private static let restIntervalKey = "restIntervalMinutes"
    private static let restHoldKey = "restHoldSeconds"
    private static let floaterHiddenKey = "floaterHidden"
    private static let floaterXKey = "floaterX"
    private static let floaterYKey = "floaterY"
    private static let restTodayKey = "restTodaySeconds"
    private static let restBucketKey = "restTodayBucket"

    static func registerDefaults() {
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        defaults.register(defaults: [
            snowfallKey: (calm ? Snowfall.light : .steady).rawValue,
            behindWindowsKey: false,
            meltSnowKey: true,
            accumulateKey: true,
            snowOnWindowsKey: true,
            showInScreenshotsKey: false,
            halloweenKey: true,
            restFirstKey: 25,
            restIntervalKey: 5,
            restHoldKey: 60,
            floaterHiddenKey: false,
        ])
    }

    static var snowfall: Snowfall {
        get { Snowfall(rawValue: defaults.integer(forKey: snowfallKey)) ?? .steady }
        set { defaults.set(newValue.rawValue, forKey: snowfallKey) }
    }

    static var snowOnWindows: Bool {
        get { defaults.bool(forKey: snowOnWindowsKey) }
        set { defaults.set(newValue, forKey: snowOnWindowsKey) }
    }

    static var accumulate: Bool {
        get { defaults.bool(forKey: accumulateKey) }
        set { defaults.set(newValue, forKey: accumulateKey) }
    }

    static var meltSnow: Bool {
        get { defaults.bool(forKey: meltSnowKey) }
        set { defaults.set(newValue, forKey: meltSnowKey) }
    }

    static var welcomed: Bool {
        get { defaults.bool(forKey: welcomedKey) }
        set { defaults.set(newValue, forKey: welcomedKey) }
    }

    static var behindWindows: Bool {
        get { defaults.bool(forKey: behindWindowsKey) }
        set { defaults.set(newValue, forKey: behindWindowsKey) }
    }

    static var showInScreenshots: Bool {
        get { defaults.bool(forKey: showInScreenshotsKey) }
        set { defaults.set(newValue, forKey: showInScreenshotsKey) }
    }

    static var halloween: Bool {
        get { defaults.bool(forKey: halloweenKey) }
        set { defaults.set(newValue, forKey: halloweenKey) }
    }

    static var restFirstMinutes: Double {
        get {
            let value = defaults.double(forKey: restFirstKey)
            return value > 0 ? value : 25
        }
        set { defaults.set(newValue, forKey: restFirstKey) }
    }

    static var restIntervalMinutes: Double {
        get {
            let value = defaults.double(forKey: restIntervalKey)
            return value > 0 ? value : 5
        }
        set { defaults.set(newValue, forKey: restIntervalKey) }
    }

    static var restHoldSeconds: Double {
        get {
            let value = defaults.double(forKey: restHoldKey)
            return value > 0 ? value : 60
        }
        set { defaults.set(newValue, forKey: restHoldKey) }
    }

    static var floaterHidden: Bool {
        get { defaults.bool(forKey: floaterHiddenKey) }
        set { defaults.set(newValue, forKey: floaterHiddenKey) }
    }

    static var floaterOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: floaterXKey) != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: floaterXKey), y: defaults.double(forKey: floaterYKey))
        }
        set {
            guard let newValue else { return }
            defaults.set(Double(newValue.x), forKey: floaterXKey)
            defaults.set(Double(newValue.y), forKey: floaterYKey)
        }
    }

    static var restToday: TimeInterval {
        get { defaults.double(forKey: restTodayKey) }
        set { defaults.set(newValue, forKey: restTodayKey) }
    }

    static var restBucket: String {
        get { defaults.string(forKey: restBucketKey) ?? "" }
        set { defaults.set(newValue, forKey: restBucketKey) }
    }
}
