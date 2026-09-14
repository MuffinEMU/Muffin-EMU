//
//  Renderer.swift
//  MeloCafe
//
//  Created by Stossy11 on 8/3/2026.
//

import Foundation

enum Renderer: Int, CaseIterable, Codable {
    case other = 0
    case vulkan = 1
    case metal = 2

    init(_ config: ObjCGraphicAPI) {
        self = Renderer(rawValue: config.rawValue) ?? .metal
    }

    var config: ObjCGraphicAPI {
        ObjCGraphicAPI(rawValue: self.rawValue) ?? .metal
    }

    var string: String {
        switch self {
        case .metal:
            return "Metal"
        case .vulkan:
            return "Vulkan"
        case .other:
            return ""
        }
    }

}
