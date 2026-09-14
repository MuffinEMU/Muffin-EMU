//
//  ConsoleLanguage.swift
//  MeloCafe
//
//  Created by Stossy11 on 11/4/2026.
//

import Foundation

enum ConsoleLanguage: Int, CaseIterable {
    case japanese = 0
    case english = 1
    case french = 2
    case german = 3
    case italian = 4
    case spanish = 5
    case chinese = 6
    case korean = 7
    case dutch = 8
    case portuguese = 9
    case russian = 10
    case taiwanese = 11

    init(_ config: ObjCCafeConsoleLanguage) {
        self = ConsoleLanguage(rawValue: config.rawValue) ?? .english
    }

    var config: ObjCCafeConsoleLanguage {
        ObjCCafeConsoleLanguage(rawValue: self.rawValue) ?? .EN
    }

    var string: String {
        switch self {
        case .japanese: return "Japanese"
        case .english: return "English"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .spanish: return "Spanish"
        case .chinese: return "Chinese"
        case .korean: return "Korean"
        case .dutch: return "Dutch"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .taiwanese: return "Taiwanese"
        }
    }
}
