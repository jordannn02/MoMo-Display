import Foundation

/// Stable display UUID -> validated user intent. Values use normalized brightness.
struct DisplayPreference: Codable, Equatable {
    var brightness: Double
    var boostRequested: Bool
    var boostMultiplier: Double

    init?(brightness: Double, boostRequested: Bool, boostMultiplier: Double) {
        guard brightness.isFinite, boostMultiplier.isFinite else { return nil }
        self.brightness = min(1, max(0.05, brightness))
        self.boostRequested = boostRequested
        self.boostMultiplier = min(1.6, max(1, boostMultiplier))
    }
}

final class DisplayPreferences {
    static let suiteName = "app.momo.display"
    static let key = "displayPreferences.v1"
    private let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        if let defaults { self.defaults = defaults }
        else if Bundle.main.bundleIdentifier == Self.suiteName { self.defaults = .standard }
        else { self.defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard }
    }

    func get(uuid: String?) -> DisplayPreference? {
        guard let uuid, let id = UUID(uuidString: uuid)?.uuidString,
              let data = defaults.data(forKey: Self.key),
              let raw = try? JSONDecoder().decode([String: DisplayPreference].self, from: data),
              let value = raw[id] else { return nil }
        return DisplayPreference(brightness: value.brightness, boostRequested: value.boostRequested,
                                 boostMultiplier: value.boostMultiplier)
    }
    func set(uuid: String?, value: DisplayPreference) {
        guard let uuid, let id = UUID(uuidString: uuid)?.uuidString,
              let safe = DisplayPreference(brightness: value.brightness, boostRequested: value.boostRequested,
                                           boostMultiplier: value.boostMultiplier) else { return }
        let data = defaults.data(forKey: Self.key)
        var all = data.flatMap { try? JSONDecoder().decode([String: DisplayPreference].self, from: $0) } ?? [:]
        all[id] = safe
        if let encoded = try? JSONEncoder().encode(all) { defaults.set(encoded, forKey: Self.key) }
    }
}
