import Foundation
import CoreGraphics

enum BrightnessTransport: String { case apple, ddc, software }
struct HardwareDisplayInfo {
    let id: CGDirectDisplayID
    let transport: BrightnessTransport
    let brightness: Double
    let detail: String
}

// All methods must be called on the same serial queue, away from the main thread.
final class BrightnessHardware: @unchecked Sendable {
    private struct DDCState { let service: IOAVService; var max: UInt16 }
    private var transports: [CGDirectDisplayID: BrightnessTransport] = [:]
    private var ddc: [CGDirectDisplayID: DDCState] = [:]

    init() {}

    func discover(displayIDs: [CGDirectDisplayID]) -> [HardwareDisplayInfo] {
        transports.removeAll(); ddc.removeAll()
        let matches = Arm64DDC.getServiceMatches(displayIDs: displayIDs)
        return displayIDs.map { id in
            var brightness: Float = 0
            if DisplayServicesGetBrightness(id, &brightness) == 0,
               brightness.isFinite, (0...1).contains(brightness) {
                transports[id] = .apple
                return HardwareDisplayInfo(id: id, transport: .apple, brightness: Double(brightness), detail: "DisplayServices")
            }
            if let match = matches.first(where: { $0.displayID == id }), let service = match.service,
               let result = Arm64DDC.read(service: service, command: 0x10) {
                transports[id] = .ddc
                ddc[id] = DDCState(service: service, max: result.max)
                return HardwareDisplayInfo(id: id, transport: .ddc, brightness: Double(result.current) / Double(result.max), detail: "DDC/CI VCP 0x10，最大值 \(result.max)")
            }
            transports[id] = .software
            return HardwareDisplayInfo(id: id, transport: .software, brightness: 1, detail: "硬體亮度不可用；使用軟體調光")
        }
    }

    func read(id: CGDirectDisplayID) -> Double? {
        switch transports[id] {
        case .apple:
            var value: Float = 0
            guard DisplayServicesGetBrightness(id, &value) == 0, value.isFinite, (0...1).contains(value) else { return nil }
            return Double(value)
        case .ddc:
            guard var state = ddc[id], let value = Arm64DDC.read(service: state.service, command: 0x10) else { return nil }
            state.max = value.max; ddc[id] = state
            return Double(value.current) / Double(value.max)
        default: return nil
        }
    }

    func set(id: CGDirectDisplayID, value: Double) -> Bool {
        guard value.isFinite else { return false }
        let clamped = max(0, min(1, value))
        switch transports[id] {
        case .apple: return DisplayServicesSetBrightness(id, Float(clamped)) == 0
        case .ddc:
            guard let state = ddc[id], state.max > 0 else { return false }
            return Arm64DDC.write(service: state.service, command: 0x10, value: UInt16((clamped * Double(state.max)).rounded()))
        default: return false
        }
    }
}
