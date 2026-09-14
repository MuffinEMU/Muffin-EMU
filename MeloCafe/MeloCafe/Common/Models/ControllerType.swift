//
//  ControllerType.swift
//  MeloCafe
//
//  Created by Stossy11 on 6/4/2026.
//


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
            return "VPAD"
        case .Pro:
            return "Pro"
        case .Classic:
            return "Classic"
        case .Wiimote:
            return "Wiimote"
        default:
            return ""
        }
    }
}
