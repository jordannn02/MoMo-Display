// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

private final class HardwareGate: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch = 0
    private var versions: [CGDirectDisplayID: Int] = [:]
    func invalidate() { lock.lock(); defer { lock.unlock() }; epoch += 1; versions.removeAll() }
    func next(_ id: CGDirectDisplayID) -> (Int, Int) {
        lock.lock(); defer { lock.unlock() }
        versions[id, default: 0] += 1
        return (epoch, versions[id]!)
    }
    func valid(_ id: CGDirectDisplayID, _ token: (Int, Int)) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return epoch == token.0 && versions[id] == token.1
    }
}

struct DisplayRow: Identifiable {
    let id: CGDirectDisplayID
    var name: String
    var uuid: String?
    var isBuiltIn: Bool
    var transport: BrightnessTransport
    var brightness: Double
    var boostLimit: Double
    var boostRequested = false
    var boostMultiplier = 1.15
    var effectiveBoost = 1.0
    var effectStatus: String?
    var error: String?
    var busy = false

    var unifiedBrightness: Double {
        boostRequested ? boostMultiplier : brightness
    }
    var unifiedBrightnessLimit: Double {
        transport == .software ? 1.0 : max(1, min(1.6, boostLimit))
    }

    var method: String {
        switch transport {
        case .apple: return "原生亮度"
        case .ddc: return "螢幕背光 · DDC"
        case .software: return "軟體調暗"
        }
    }
}

@MainActor final class DisplayModel: ObservableObject {
    @Published var displays: [DisplayRow] = []
    @Published var scanning = false
    @Published var message: String?
    private let preferences = DisplayPreferences()
    private let hardware = BrightnessHardware()
    private let queue = DispatchQueue(label: "app.momo.display.hardware", qos: .userInitiated)
    private let effects = DisplayEffects()
    private let hardwareGate = HardwareGate()
    private var pending: [CGDirectDisplayID: DispatchWorkItem] = [:]
    private var generation = 0
    private var revisions: [CGDirectDisplayID: Int] = [:]
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var topology = ""
    private var suspended = false

    init() {
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.suspended else { return }
                if self.currentTopology != self.topology { self.refresh() }
            }
        })
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.suspended = false; self?.refresh() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateEffects() }
        }
        refresh()
    }

    private var currentTopology: String {
        NSScreen.screens.map { "\($0.displayID):\($0.frame)" }.joined(separator: "|")
    }

    func refresh() {
        guard !suspended else { return }
        cancelPending()
        effects.resetAll()
        generation += 1
        let ticket = generation
        let screens = NSScreen.screens
        topology = currentTopology
        scanning = true
        message = nil
        let identifiers = screens.map(\.displayID)
        let identities = Dictionary(uniqueKeysWithValues: screens.map { ($0.displayID, displayUUID($0.displayID)) })
        let saved = Dictionary(uniqueKeysWithValues: screens.compactMap { screen -> (CGDirectDisplayID, DisplayPreference)? in
            guard let value = preferences.get(uuid: identities[screen.displayID] ?? nil) else { return nil }
            return (screen.displayID, value)
        })
        let tokens = Dictionary(uniqueKeysWithValues: identifiers.map { ($0, hardwareGate.next($0)) })
        // Do not allow input against old rows while their hardware identities are being rediscovered.
        displays = []
        queue.async { [hardware, gate = hardwareGate, weak self] in
            let results = hardware.discover(displayIDs: identifiers)
            var restored: [CGDirectDisplayID: (Double?, Bool)] = [:]
            for info in results {
                guard let preference = saved[info.id], info.transport != .software,
                      let token = tokens[info.id], gate.valid(info.id, token),
                      displayUUID(info.id) == (identities[info.id] ?? nil) else { continue }
                let target = preference.boostRequested ? 1.0 : preference.brightness
                let success = hardware.set(id: info.id, value: target)
                let actual = hardware.read(id: info.id)
                restored[info.id] = (actual, success && actual != nil && abs(actual! - target) <= 0.035)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, ticket == self.generation else { return }
                self.displays = NSScreen.screens.filter { identifiers.contains($0.displayID) && displayUUID($0.displayID) == (identities[$0.displayID] ?? nil) }.map { screen in
                    let info = results.first { $0.id == screen.displayID }
                    let preference = saved[screen.displayID]
                    let result = restored[screen.displayID]
                    let transport = info?.transport ?? .software
                    let brightness = transport == .software ? (preference?.brightness ?? 1) : (result?.0 ?? info?.brightness ?? 1)
                    var row = DisplayRow(id: screen.displayID, name: screen.localizedName, uuid: identities[screen.displayID] ?? nil,
                                         isBuiltIn: CGDisplayIsBuiltin(screen.displayID) != 0,
                                         transport: transport, brightness: brightness,
                                         boostLimit: self.effects.boostCapability(screen: screen))
                    row.boostMultiplier = preference?.boostMultiplier ?? 1.15
                    row.boostRequested = preference?.boostRequested ?? false
                    if preference != nil, transport != .software, result?.1 != true {
                        row.error = result?.0 == nil ? "還原亮度未獲確認，顯示最後讀值；未啟用 XDR。" : "還原亮度未獲確認，已顯示實際讀值；未啟用 XDR。"
                    }
                    return row
                }
                self.scanning = false
                for row in self.displays {
                    guard let screen = NSScreen.screens.first(where: { $0.displayID == row.id }) else { continue }
                    if row.transport == .software { self.effects.setSoftwareDim(screen: screen, brightness: row.brightness) }
                    if saved[row.id]?.boostRequested == true && (row.transport == .software || restored[row.id]?.1 == true) {
                        self.applyBoost(id: row.id)
                    }
                }
                if self.displays.isEmpty { self.message = "目前沒有可用的螢幕。" }
            }
        }
    }

    private func save(_ index: Int, brightness: Bool = false, boost: Bool = false, multiplier: Bool = false) {
        let row = displays[index]
        let old = preferences.get(uuid: row.uuid)
        if let value = DisplayPreference(brightness: brightness ? row.brightness : (old?.brightness ?? row.brightness),
                                         boostRequested: boost ? row.boostRequested : (old?.boostRequested ?? row.boostRequested),
                                         boostMultiplier: multiplier ? row.boostMultiplier : (old?.boostMultiplier ?? row.boostMultiplier)) {
            preferences.set(uuid: row.uuid, value: value)
        }
    }

    /// A single normalized slider: 0.05–1.0 controls brightness, above 1.0 requests XDR.
    func changeUnifiedBrightness(id: CGDirectDisplayID, value: Double) {
        guard value.isFinite, !suspended, let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let limit = displays[index].unifiedBrightnessLimit
        let requested = min(limit, max(0.05, value))
        let wantsBoost = requested > 1.0
        // Invalidate any older queued boost callback before changing effects or hardware.
        pending[id]?.cancel()
        revisions[id, default: 0] += 1
        _ = hardwareGate.next(id)
        if !wantsBoost { effects.reset(displayID: id) }
        displays[index].boostRequested = wantsBoost
        displays[index].boostMultiplier = wantsBoost ? requested : 1.0
        displays[index].brightness = min(1, requested)
        if !wantsBoost { displays[index].effectiveBoost = 1; displays[index].effectStatus = nil }
        save(index, brightness: true, boost: true, multiplier: true)
        guard !effects.hasPendingRestore() else {
            displays[index].busy = false
            displays[index].error = "無法確認先前的 XDR 色彩表已還原，未變更硬體亮度。"
            return
        }
        changeBrightness(id: id, value: min(1, requested), boostAfterReadback: wantsBoost)
    }

    func changeBrightness(id: CGDirectDisplayID, value: Double, boostAfterReadback: Bool = false) {
        guard value.isFinite, !suspended, let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let value = min(1, max(0.05, value))
        displays[index].brightness = value
        displays[index].error = nil
        save(index, brightness: true)
        if displays[index].transport == .software {
            if let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
                effects.setSoftwareDim(screen: screen, brightness: value)
            }
            return
        }
        pending[id]?.cancel()
        revisions[id, default: 0] += 1
        let revision = revisions[id]!
        let token = hardwareGate.next(id)
        let ticket = generation
        displays[index].busy = true
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Check on the main actor before submitting to the serialized hardware queue.
            guard ticket == self.generation, self.revisions[id] == revision, !self.suspended else { return }
            self.queue.async { [hardware = self.hardware, gate = self.hardwareGate, weak self] in
                guard gate.valid(id, token) else { return }
                let success = hardware.set(id: id, value: value)
                let readback = hardware.read(id: id)
                DispatchQueue.main.async { [weak self] in
                    guard let self, ticket == self.generation, self.revisions[id] == revision,
                          let index = self.displays.firstIndex(where: { $0.id == id }) else { return }
                    self.displays[index].busy = false
                    if let readback { self.displays[index].brightness = readback }
                    if !success || readback == nil {
                        self.displays[index].error = "螢幕未確認亮度變更，請檢查連線或重新偵測。"
                    } else if abs(readback! - value) > 0.035 {
                        self.displays[index].error = "螢幕回報的亮度不同，已顯示實際讀值；XDR 設定未更新。"
                    } else if boostAfterReadback && self.displays[index].boostRequested {
                        self.applyBoost(id: id)
                    }
                }
            }
        }
        pending[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    func toggleBoost(id: CGDirectDisplayID, enabled: Bool) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[index].boostRequested = enabled
        save(index, boost: true)
        if enabled { applyBoost(id: id) }
        else {
            // Resetting boost also removes software dim; restore that independent intent.
            effects.reset(displayID: id)
            if displays[index].transport == .software, let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
                effects.setSoftwareDim(screen: screen, brightness: displays[index].brightness)
            }
            displays[index].effectiveBoost = 1
            displays[index].effectStatus = effects.status(displayID: id)
        }
    }

    private func applyBoost(id: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == id }),
              let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return }
        displays[index].boostRequested = true
        displays[index].error = nil
        do {
            try effects.setBoost(screen: screen, multiplier: min(displays[index].boostMultiplier, displays[index].boostLimit))
        } catch {
            // Keep the switch aligned with saved intent, so it can still be explicitly turned off.
            displays[index].error = "XDR 尚未啟用：\(error.localizedDescription)"
        }
        updateEffects()
    }

    func changeBoost(id: CGDirectDisplayID, value: Double) {
        guard let index = displays.firstIndex(where: { $0.id == id }), value.isFinite else { return }
        displays[index].boostMultiplier = min(1.6, max(1, value))
        save(index, multiplier: true)
        if displays[index].boostRequested { applyBoost(id: id) }
    }

    private func updateEffects() {
        for index in displays.indices {
            let id = displays[index].id
            var status = effects.status(displayID: id)
            let effective = effects.effectiveBoost(displayID: id)
            if displays[index].boostRequested && !effects.isBoostRequested(displayID: id) {
                status = status ??
                    (displays[index].boostMultiplier <= 1.001 ? "100%，未加額外增益" : "XDR 尚未啟用；可重新偵測或將亮度調回 100% 以下。")
            }
            if displays[index].effectStatus != status { displays[index].effectStatus = status }
            if displays[index].effectiveBoost != effective { displays[index].effectiveBoost = effective }
        }
    }

    func stopEffects() {
        effects.resetAll()
        let failures = effects.restoreFailures()
        message = failures.isEmpty ? nil : failures.joined(separator: "\n")
        for index in displays.indices {
            displays[index].boostRequested = false
            displays[index].effectiveBoost = 1
            displays[index].effectStatus = effects.status(displayID: displays[index].id)
            if displays[index].transport == .software { displays[index].brightness = 1 }
            save(index, brightness: displays[index].transport == .software, boost: true)
        }
    }

    private func cancelPending() {
        hardwareGate.invalidate()
        for item in pending.values { item.cancel() }
        pending.removeAll()
    }

    private func suspend() {
        suspended = true
        generation += 1
        cancelPending()
        effects.resetAll()
    }

    func shutdown() {
        suspend()
        timer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        // Drain any hardware write already in progress before the app exits.
        queue.sync {}
    }

    func prepareForQuit() -> Bool {
        effects.resetAll()
        let failures = effects.restoreFailures()
        message = failures.isEmpty ? nil : failures.joined(separator: "\n")
        return !effects.hasPendingRestore()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

private func displayUUID(_ id: CGDirectDisplayID) -> String? {
    guard id != 0, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
}
