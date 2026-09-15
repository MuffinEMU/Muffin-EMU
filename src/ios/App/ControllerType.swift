import Foundation

/// A Wii U controller role a physical (or the emulated GamePad's own) controller can
/// be assigned to. Raw values are pinned to the core's EmulatedController::Type
/// (src/input/emulated/EmulatedController.h) and to GCBridgeControllerDesc's
/// controllerType field (CemuBridge.h) - both cross the Swift/C++ boundary as a bare
/// uint8, so this enum's cases and order can never drift from that header without
/// silently reassigning every controller's role.
enum ControllerType: UInt8, CaseIterable, Identifiable {
    static let allCases: [ControllerType] = [.VPAD, .Pro, .Classic, .Wiimote]

    var id: UInt8 { self.rawValue }

    case VPAD = 0
    case Pro = 1
    case Classic = 2
    case Wiimote = 3
    case MAX = 4

    var name: String {
        switch self {
        case .VPAD:
            return "GamePad"
        case .Pro:
            return "Pro Controller"
        case .Classic:
            return "Classic Controller"
        case .Wiimote:
            return "Wiimote"
        default:
            return ""
        }
    }
}
