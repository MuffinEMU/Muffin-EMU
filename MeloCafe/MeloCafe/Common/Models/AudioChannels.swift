//
//  AudioChannels.swift
//  MeloCafe
//
//  Created by Stossy11 on 11/4/2026.
//

import Foundation

enum AudioChannels: Int, CaseIterable {
    case mono = 0
    case stereo = 1
    case surround = 2

    init(_ config: ObjCAudioChannels) {
        self = AudioChannels(rawValue: config.rawValue) ?? .stereo
    }

    var config: ObjCAudioChannels {
        ObjCAudioChannels(rawValue: self.rawValue) ?? .stereo
    }

    var string: String {
        switch self {
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        case .surround: return "Surround"
        }
    }
}
