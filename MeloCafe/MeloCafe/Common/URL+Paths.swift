//
//  URL+Paths.swift
//  MeloCafe
//
//  Created by Stossy11 on 14/9/2026.
//

import Foundation

extension URL {
    static var romsURL: URL {
        .documentsDirectory.appendingPathComponent("roms")
    }
    
    static var configURL: URL {
        .documentsDirectory.appendingPathComponent("config.xml")
    }
}
