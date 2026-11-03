import Foundation

@main struct PreferenceTests {
    static func main() {
        let suite = "app.momo.display.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = DisplayPreferences(defaults: defaults)
        let first = UUID().uuidString, second = UUID().uuidString
        let a = DisplayPreference(brightness: 0.37, boostRequested: true, boostMultiplier: 1.35)!
        let b = DisplayPreference(brightness: 0.8, boostRequested: false, boostMultiplier: 1.1)!
        prefs.set(uuid: first.lowercased(), value: a)
        prefs.set(uuid: second, value: b)
        precondition(prefs.get(uuid: first) == a && prefs.get(uuid: second) == b)
        prefs.set(uuid: nil, value: b)
        prefs.set(uuid: "bad", value: b)
        precondition(prefs.get(uuid: nil) == nil && prefs.get(uuid: "bad") == nil)
        precondition(DisplayPreference(brightness: .nan, boostRequested: true, boostMultiplier: 1) == nil)
        precondition(DisplayPreference(brightness: 1, boostRequested: true, boostMultiplier: .infinity) == nil)
        let clamped = DisplayPreference(brightness: -1, boostRequested: true, boostMultiplier: 9)!
        precondition(clamped.brightness == 0.05 && clamped.boostMultiplier == 1.6)
        let loaded = DisplayPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(loaded.get(uuid: first) == a && loaded.get(uuid: second) == b)
        print("Preference tests passed")
    }
}
