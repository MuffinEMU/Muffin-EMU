//
//  CPUMode.swift
//  MeloCafe
//
//  Created by Stossy11 on 25/4/2026.
//

import Foundation

public enum CPUMode: Int, CaseIterable {
    case interpreter
    case recompiler
    case auto

    init(_ cpuMode: ObjCCPUMode) {
        switch cpuMode {
        case .singlecoreInterpreter, .multicoreInterpreter: self = .interpreter
        case .auto: self = .auto
        default: self = .recompiler
        }
    }

    var config: ObjCCPUMode {
        switch self {
        case .interpreter: return .multicoreInterpreter
        case .recompiler: return .multicoreRecompiler
        case .auto: return .auto
        }
    }

    var string: String {
        switch self {
        case .interpreter: return "Interpreter"
        case .recompiler: return "Recompiler (JIT)"
        case .auto: return "Auto"
        }
    }
}
