//
//  ScreenPosition.swift
//  MeloCafe
//
//  Created by Stossy11 on 11/4/2026.
//

import Foundation

enum ScreenPosition: Int, CaseIterable {
    case disabled = 0
    case topLeft = 1
    case topCenter = 2
    case topRight = 3
    case bottomLeft = 4
    case bottomCenter = 5
    case bottomRight = 6

    init(_ config: ObjCScreenPosition) {
        self = ScreenPosition(rawValue: config.rawValue) ?? .disabled
    }

    var config: ObjCScreenPosition {
        ObjCScreenPosition(rawValue: self.rawValue) ?? .disabled
    }

    var string: String {
        switch self {
        case .disabled: return "Disabled"
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }
}
