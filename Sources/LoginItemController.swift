// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ServiceManagement
import SwiftUI

@MainActor final class LoginItemController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var message: String?

    init() { refresh() }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
        if needsApproval { message = "請在系統設定的登入項目中允許啟動。" }
    }

    func setEnabled(_ value: Bool) {
        message = nil
        do {
            if value {
                guard Bundle.main.bundleURL.path == "/Applications/MoMo Display.app" else {
                    message = "請先將 MoMo Display 放入「應用程式」再啟用。"
                    return
                }
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            message = "登入啟動設定失敗：\(error.localizedDescription)"
        }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
    static var statusName: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }
}
