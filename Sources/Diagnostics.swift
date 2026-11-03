// SPDX-License-Identifier: GPL-3.0-only
import AppKit

func emitJSON(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
       let string = String(data: data, encoding: .utf8) { print(string) }
}

@MainActor func runDiagnostics() {
    let hardware = BrightnessHardware()
    let preferences = DisplayPreferences()
    let screens = NSScreen.screens
    let info = hardware.discover(displayIDs: screens.map(\.displayID))
    emitJSON(screens.map { screen -> [String: Any] in
        let item = info.first { $0.id == screen.displayID }
        let uuid = CGDisplayCreateUUIDFromDisplayID(screen.displayID).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        let saved = preferences.get(uuid: uuid)
        return ["id": screen.displayID, "name": screen.localizedName,
                "uuid": uuid ?? "", "savedBrightness": saved?.brightness ?? -1,
                "savedBoostRequested": saved?.boostRequested ?? false,
                "savedBoostMultiplier": saved?.boostMultiplier ?? 1,
                "gammaMaximum": gamma(screen.displayID)?.max() ?? -1,
                "builtIn": CGDisplayIsBuiltin(screen.displayID) != 0,
                "transport": item?.transport.rawValue ?? "unknown",
                "brightness": item?.brightness ?? -1,
                "detail": item?.detail ?? "",
                "edrCurrent": screen.maximumExtendedDynamicRangeColorComponentValue,
                "edrPotential": screen.maximumPotentialExtendedDynamicRangeColorComponentValue]
    })
}

@MainActor func runHardwareSelfTest() {
    let hardware = BrightnessHardware()
    let discovered = hardware.discover(displayIDs: NSScreen.screens.map(\.displayID))
    var rows: [[String: Any]] = []
    for item in discovered where item.transport != .software {
        guard let before = hardware.read(id: item.id) else { continue }
        let target = before > 0.1 ? before - 0.02 : before + 0.02
        let wrote = hardware.set(id: item.id, value: target)
        Thread.sleep(forTimeInterval: 0.2)
        let changed = hardware.read(id: item.id)
        var restored = false
        var after: Double?
        for _ in 0..<3 {
            _ = hardware.set(id: item.id, value: before)
            Thread.sleep(forTimeInterval: 0.15)
            after = hardware.read(id: item.id)
            if let after, abs(after - before) < 0.015 { restored = true; break }
        }
        rows.append(["id": item.id, "before": before, "target": target,
                     "writeReturnedSuccess": wrote, "readback": changed ?? -1,
                     "afterRestore": after ?? -1, "restored": restored,
                     "changeVerified": changed.map { abs($0 - target) < 0.015 } ?? false])
        if !restored { emitJSON(rows); exit(2) }
    }
    emitJSON(rows)
}

private func gamma(_ id: CGDirectDisplayID) -> [Float]? {
    var r = [Float](repeating: 0, count: 256), g = [Float](repeating: 0, count: 256), b = [Float](repeating: 0, count: 256)
    var count: UInt32 = 0
    guard CGGetDisplayTransferByTable(id, 256, &r, &g, &b, &count) == .success else { return nil }
    return Array(r.prefix(Int(count))) + Array(g.prefix(Int(count))) + Array(b.prefix(Int(count)))
}

@MainActor func runEffectsSelfTest() {
    let effects = DisplayEffects()
    guard let screen = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }),
          let original = gamma(screen.displayID) else { print("No internal display/gamma"); exit(2) }
    let id = screen.displayID
    do { try effects.setBoost(screen: screen, multiplier: 1.05) }
    catch { print(error.localizedDescription); exit(2) }
    var samples: [[String: Any]] = []
    let start = Date()
    var timer: Timer?
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        MainActor.assumeIsolated {
            let elapsed = Date().timeIntervalSince(start)
            samples.append(["second": Int(elapsed), "status": effects.status(displayID: id) ?? "none",
                            "requested": effects.isBoostRequested(displayID: id),
                            "effective": effects.effectiveBoost(displayID: id),
                            "headroom": screen.maximumExtendedDynamicRangeColorComponentValue,
                            "gammaMax": gamma(id)?.max() ?? -1])
            if elapsed >= 12 {
                timer?.invalidate()
                effects.resetAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let after = gamma(id) ?? []
                    let restored = after.count == original.count && zip(after, original).allSatisfy { abs($0 - $1) < 0.015 }
                    emitJSON(["samples": samples, "restored": restored, "finalGammaMax": after.max() ?? -1])
                    exit(restored ? 0 : 2)
                }
            }
        }
    }
    NSApplication.shared.run()
}
