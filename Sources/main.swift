// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

private let accent = Color(red: 0.98, green: 0.50, blue: 0.24)

struct BrightnessPanel: View {
    @ObservedObject var model: DisplayModel
    @ObservedObject var login: LoginItemController
    var panelHeight: CGFloat
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill").font(.system(size: 24)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MoMo Display").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("剛剛好的亮度，每一個螢幕。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("重新偵測螢幕並恢復已記住的設定")
                    .disabled(model.scanning)
            }
            if model.scanning {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("正在讀取螢幕亮度…").font(.callout) }
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                    VStack(spacing: 12) {
                        ForEach(model.displays) { display in displayCard(display) }
                    }
            }
            if let message = model.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Text("\(model.displays.count) 個螢幕").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("設定自動儲存").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("登入時自動啟動", isOn: Binding(get: { login.enabled }, set: login.setEnabled))
                .toggleStyle(.switch).controlSize(.small).font(.caption).tint(accent)
            Text("自動記住每個螢幕的亮度與 XDR 設定")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if let message = login.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if login.needsApproval {
                Button("開啟登入項目設定", action: login.openSettings).font(.caption)
            }
            HStack {
                Button("關於與授權") { showAbout() }.buttonStyle(.plain)
                Spacer()
                Button("結束") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(maxWidth: .infinity)
        }
        .frame(width: 380, height: panelHeight)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func displayCard(_ row: DisplayRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: row.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 22)).frame(width: 30)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(row.method).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if row.busy { ProgressView().controlSize(.mini) }
                Text("\(Int((row.unifiedBrightness * 100).rounded()))%")
                    .font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
            }
            HStack(spacing: 9) {
                Image(systemName: "sun.min").font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { row.unifiedBrightness }, set: { model.changeUnifiedBrightness(id: row.id, value: ($0 * 100).rounded() / 100) }), in: 0.05...row.unifiedBrightnessLimit)
                    .tint(accent).accessibilityLabel("\(row.name) 亮度")
                Image(systemName: "sun.max.fill").font(.system(size: 15)).foregroundStyle(accent)
            }
            if row.boostLimit > 1.01 && row.transport != .software {
                HStack(spacing: 8) {
                    ForEach([100, 110, 120], id: \.self) { percent in
                        Button("\(percent)%") { model.changeUnifiedBrightness(id: row.id, value: Double(percent) / 100) }
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                    Spacer()
                }
                Text(row.boostRequested ? (row.effectStatus ?? "正在套用亮度…") : "100% 為標準亮度；往上調整會自動使用 XDR。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if row.transport == .software {
                Text("目前無法控制螢幕背光，使用軟體調暗；100% 為原始畫面。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("此螢幕沒有可用的 XDR 額外亮度空間。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let error = row.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MoMo Display \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        alert.informativeText = "只做螢幕亮度控制。\n\n硬體調光：改寫自 MonitorControl（MIT）。\nXDR 增亮：改寫自 BrightIntosh（GPL-3.0）。\n\nMoMo Display 以 GPL-3.0 提供完整原始碼。\n增亮倍率不代表實測 nits，實際亮度由面板與 macOS 決定。\n\n睡眠、登出與結束時會還原畫面效果；下次啟動、喚醒或重新連線會恢復已記住的設定。"
        alert.addButton(withTitle: "完成")
        alert.addButton(withTitle: "授權文件")
        if alert.runModal() == .alertSecondButtonReturn,
           let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses") { NSWorkspace.shared.open(url) }
    }
}

private final class MenuControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: MenuControlPanel!
    private var model: DisplayModel!
    private var login: LoginItemController!
    private var window: NSWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Do not let two menu-bar processes compete for the same gamma table.
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "app.momo.display")
        if existing.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?.activate()
            NSApp.terminate(nil)
            return
        }
        model = DisplayModel()
        login = LoginItemController()
        if CommandLine.arguments.contains("--enable-login") { login.setEnabled(true) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "MoMo Display")
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.toolTip = "MoMo Display · 螢幕亮度"
        panel = MenuControlPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.title = "MoMo Display"
        if CommandLine.arguments.contains("--window") {
            let controller = NSHostingController(rootView: BrightnessPanel(model: model, login: login, panelHeight: 620))
            let window = NSWindow(contentViewController: controller)
            window.title = "MoMo Display"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
        } else if CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--enable-login") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel() }
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = item.button, let anchorWindow = button.window,
              let screen = anchorWindow.screen else { return }
        login.refresh()
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let top = min(anchor.minY, visible.maxY) - 6
        let height = min(540, max(100, top - visible.minY - 8))
        let width: CGFloat = min(380, visible.width - 16)
        let x = min(max(anchor.maxX - width, visible.minX + 8), visible.maxX - width - 8)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        panel.contentViewController = NSHostingController(rootView: BrightnessPanel(model: model, login: login, panelHeight: height))
        panel.setFrame(frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if CommandLine.arguments.contains("--diagnostic-geometry") {
            UserDefaults.standard.set(["top": panel.frame.maxY, "menuBottom": anchor.minY,
                                       "visibleTop": visible.maxY, "height": height,
                                       "pid": Double(ProcessInfo.processInfo.processIdentifier)], forKey: "lastPanelGeometry")
        }
        installDismissMonitors()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
    }

    private func installDismissMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                if event.type == .keyDown && event.keyCode == 53 { self.hidePanel(); return nil }
                if event.type != .keyDown, event.window !== self.panel, event.window !== self.item.button?.window { self.hidePanel() }
                return event
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.hidePanel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { hidePanel(); model?.shutdown() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.prepareForQuit() { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "尚未確認亮度效果已還原"
        alert.informativeText = model.message ?? "請重試還原後再結束。"
        alert.addButton(withTitle: "重試還原")
        alert.addButton(withTitle: "留在程式")
        if alert.runModal() == .alertFirstButtonReturn, model.prepareForQuit() { return .terminateNow }
        return .terminateCancel
    }
}

MainActor.assumeIsolated {
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
if CommandLine.arguments.contains("--diagnose") {
    runDiagnostics()
} else if CommandLine.arguments.contains("--login-status") {
    emitJSON(["path": Bundle.main.bundlePath, "loginItemStatus": LoginItemController.statusName])
} else if CommandLine.arguments.contains("--hardware-self-test") {
    runHardwareSelfTest()
} else if CommandLine.arguments.contains("--effects-self-test") {
    runEffectsSelfTest()
} else {
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    application.run()
}
}
