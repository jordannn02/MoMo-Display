// EDR trigger and gamma approach adapted from BrightIntosh by Niklas Rousset
// and contributors, https://github.com/niklasr22/Brightintosh, GPL-3.0.
// See Licenses/BrightIntosh-GPL-3.0.txt.
import AppKit
import CoreGraphics
import MetalKit
import QuartzCore

private enum EffectsError: LocalizedError {
    case unsupported, invalid, gamma, metal
    var errorDescription: String? {
        switch self {
        case .unsupported: return "此顯示器目前不支援 XDR 增亮"
        case .invalid: return "增亮倍率無效"
        case .gamma: return "無法讀取或設定顯示器 gamma"
        case .metal: return "無法建立 Metal EDR 觸發視窗"
        }
    }
}

private func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}

private func displayIdentity(_ id: CGDirectDisplayID) -> String? {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
}

private struct GammaSnapshot {
    let red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]
    static func capture(_ id: CGDirectDisplayID) -> GammaSnapshot? {
        let capacity: UInt32 = 256
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count) == .success,
              count > 1, count <= capacity else { return nil }
        return GammaSnapshot(red: Array(r.prefix(Int(count))), green: Array(g.prefix(Int(count))), blue: Array(b.prefix(Int(count))))
    }
    func apply(_ id: CGDirectDisplayID, factor: Double) -> Bool {
        let f = Float(factor)
        let r = red.map { $0 * f }, g = green.map { $0 * f }, b = blue.map { $0 * f }
        return CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b) == .success
    }
    func matches(_ other: GammaSnapshot, factor: Double) -> Bool {
        guard red.count == other.red.count else { return false }
        for (source, current) in [(red, other.red), (green, other.green), (blue, other.blue)] {
            for i in source.indices where abs(current[i] - source[i] * Float(factor)) > 0.012 { return false }
        }
        return true
    }
}

private final class EDRView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private(set) var rendered = false
    init?(triggerFrame frame: CGRect) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        super.init(frame: frame, device: device)
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        clearColor = MTLClearColorMake(1.6, 1.6, 1.6, 1)
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        preferredFramesPerSecond = 5
        delegate = self
        guard let metalLayer = layer as? CAMetalLayer else { return nil }
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.isOpaque = false
        metalLayer.pixelFormat = .rgba16Float
    }
    required init(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func draw(in view: MTKView) {
        guard let descriptor = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.addCompletedHandler { [weak self] buffer in
            guard buffer.status == .completed else { return }
            DispatchQueue.main.async { self?.rendered = true }
        }
        buffer.commit()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

@MainActor final class DisplayEffects {
    private final class BoostState {
        let snapshot: GammaSnapshot
        let identity: String
        let window: NSWindow
        let view: EDRView
        var requested: Double
        var applied: Double = 1
        var attempted: Double?
        var task: Task<Void, Never>?
        init(snapshot: GammaSnapshot, identity: String, window: NSWindow, view: EDRView, requested: Double) {
            self.snapshot = snapshot; self.identity = identity; self.window = window; self.view = view; self.requested = requested
        }
    }
    private var boosts: [CGDirectDisplayID: BoostState] = [:]
    private var dims: [CGDirectDisplayID: NSWindow] = [:]
    private var messages: [CGDirectDisplayID: String] = [:]
    private struct PendingRestore {
        let snapshot: GammaSnapshot
        let factors: [Double]
        let identity: String
    }
    private var pending: [CGDirectDisplayID: PendingRestore] = [:]
    private var restorationIssues: [CGDirectDisplayID: String] = [:]
    init() {}

    func boostCapability(screen: NSScreen) -> Double {
        guard let id = displayID(screen), CGDisplayIsBuiltin(id) != 0,
              CGDisplayIsAsleep(id) == 0 else { return 1 }
        let potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        return potential.isFinite ? max(1, min(1.6, potential)) : 1
    }
    func setBoost(screen: NSScreen, multiplier: Double) throws {
        guard let id = displayID(screen), multiplier.isFinite, multiplier >= 1 else { throw EffectsError.invalid }
        if multiplier <= 1.001 { resetBoost(id); messages[id] = nil; return }
        guard pending[id] == nil else { throw EffectsError.gamma }
        let cap = boostCapability(screen: screen)
        guard cap > 1.05 else { throw EffectsError.unsupported }
        let requested = min(multiplier, cap)
        if let state = boosts[id] {
            state.requested = requested
            messages[id] = "正在調整 XDR 增亮"
            return
        }
        guard let snapshot = GammaSnapshot.capture(id), let identity = displayIdentity(id) else { throw EffectsError.gamma }
        let rect = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1)
        guard let view = EDRView(triggerFrame: NSRect(x: 0, y: 0, width: 1, height: 1)) else { throw EffectsError.metal }
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.setAccessibilityHidden(true)
        window.contentView = view
        let state = BoostState(snapshot: snapshot, identity: identity, window: window, view: view, requested: requested)
        boosts[id] = state
        messages[id] = "等待 XDR 啟用"
        window.orderFrontRegardless(); view.draw()
        state.task = Task { @MainActor [weak self, weak state] in
            guard let self, let state else { return }
            let deadline = Date().addingTimeInterval(10)
            var active = false
            while !Task.isCancelled {
                guard let screen = NSScreen.screens.first(where: { displayID($0) == id }), CGDisplayIsAsleep(id) == 0,
                      displayIdentity(id) == state.identity else {
                    self.fail(id, "顯示器離線或休眠，已停止增亮"); return
                }
                let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
                if state.view.rendered && headroom > 1.05 {
                    let factor = min(state.requested, 1.6, headroom)
                    if active, let current = GammaSnapshot.capture(id), !state.snapshot.matches(current, factor: state.applied) {
                        self.fail(id, "Gamma 已由其他程式更改，已停止增亮", restore: false); return
                    }
                    if abs(factor - state.applied) > 0.002 {
                        state.attempted = factor
                        guard state.snapshot.apply(id, factor: factor) else {
                            self.fail(id, "Gamma 設定失敗，已停止增亮"); return
                        }
                        guard let current = GammaSnapshot.capture(id), state.snapshot.matches(current, factor: factor) else {
                            self.fail(id, "Gamma 寫入無法驗證，已停止增亮"); return
                        }
                        state.applied = factor
                        state.attempted = nil
                    }
                    active = true
                    self.messages[id] = String(format: "XDR 亮度 %.0f%% 已啟用", state.applied * 100)
                } else if active {
                    self.fail(id, "XDR headroom 已消失，已停止增亮"); return
                } else if Date() >= deadline {
                    self.fail(id, "XDR 未啟用，已停止增亮"); return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
    func setSoftwareDim(screen: NSScreen, brightness: Double) {
        guard let id = displayID(screen), brightness.isFinite else { return }
        let value = min(1, max(0.05, brightness))
        guard value < 0.999 else { dims.removeValue(forKey: id)?.close(); return }
        let window: NSWindow
        if let existing = dims[id] { window = existing; window.setFrame(screen.frame, display: true) }
        else {
            window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
            window.isOpaque = false; window.hasShadow = false; window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
            window.isExcludedFromWindowsMenu = true
            window.setAccessibilityHidden(true)
            dims[id] = window
        }
        window.backgroundColor = NSColor.black.withAlphaComponent(1 - value)
        window.orderFrontRegardless()
    }
    func reset(displayID id: CGDirectDisplayID) {
        resetBoost(id)
        dims.removeValue(forKey: id)?.close()
        if pending[id] != nil { retryRestore(id) }
        if restorationIssues[id] == nil { messages[id] = nil }
    }
    func resetAll() {
        for id in Set(boosts.keys).union(dims.keys).union(pending.keys) { reset(displayID: id) }
    }
    func status(displayID: CGDirectDisplayID) -> String? { messages[displayID] }
    func isBoostRequested(displayID: CGDirectDisplayID) -> Bool { boosts[displayID] != nil }
    func effectiveBoost(displayID: CGDirectDisplayID) -> Double { boosts[displayID]?.applied ?? 1 }
    // A pending restoration must be resolved before normal termination.
    func hasPendingRestore() -> Bool { !pending.isEmpty }
    func restoreFailures() -> [String] { restorationIssues.keys.sorted().compactMap { restorationIssues[$0] } }
    private func fail(_ id: CGDirectDisplayID, _ message: String, restore: Bool = true) {
        resetBoost(id, restore: restore)
        messages[id] = restorationIssues[id].map { "\(message)；\($0)" } ?? message
    }
    private func resetBoost(_ id: CGDirectDisplayID, restore: Bool = true) {
        guard let state = boosts.removeValue(forKey: id) else { return }
        state.task?.cancel()
        state.window.close()
        if restore && (state.applied > 1 || state.attempted != nil) {
            var factors = [state.applied]
            if let attempted = state.attempted { factors.append(attempted) }
            pending[id] = PendingRestore(snapshot: state.snapshot, factors: factors, identity: state.identity)
            retryRestore(id)
        }
    }
    private func retryRestore(_ id: CGDirectDisplayID) {
        guard let item = pending[id] else { return }
        // Keep the original table across sleep/disconnection; do not write to a reused ID.
        guard CGDisplayIsOnline(id) != 0 else {
            let issue = "顯示器 \(id) 已離線；保留還原資料，請重新連線後重試"
            restorationIssues[id] = issue; messages[id] = issue
            return
        }
        guard displayIdentity(id) == item.identity else {
            let issue = "顯示器 \(id) 身分已改變；保留原始還原資料，未寫入其他螢幕"
            restorationIssues[id] = issue; messages[id] = issue
            return
        }
        var reason = "無法讀取 gamma"
        for _ in 0..<3 {
            guard let current = GammaSnapshot.capture(id) else { reason = "無法讀取 gamma"; continue }
            if item.snapshot.matches(current, factor: 1) {
                pending.removeValue(forKey: id); restorationIssues[id] = nil
                return
            }
            guard item.factors.contains(where: { item.snapshot.matches(current, factor: $0) }) else {
                reason = "gamma 已變更或無法辨識；未覆蓋目前色彩表"
                break
            }
            guard item.snapshot.apply(id, factor: 1) else { reason = "gamma 還原寫入失敗"; continue }
            guard let verified = GammaSnapshot.capture(id) else { reason = "gamma 還原後無法讀回"; continue }
            if item.snapshot.matches(verified, factor: 1) {
                pending.removeValue(forKey: id); restorationIssues[id] = nil
                return
            }
            reason = "gamma 還原後讀回不符"
        }
        let issue = "顯示器 \(id)：\(reason)，可重試還原"
        restorationIssues[id] = issue; messages[id] = issue
    }
}
