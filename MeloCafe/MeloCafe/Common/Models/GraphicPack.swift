//
//  GraphicPack.swift
//  MeloCafe
//
//  Created by Stossy11 on 11/4/2026.
//

import Foundation

struct GraphicPackPreset: Identifiable {
    let category: String
    let name: String
    var active: Bool
    var visible: Bool
    let isDefault: Bool

    var id: String { "\(category)/\(name)" }

    init(_ entry: GraphicPackPresetEntry) {
        self.category = entry.category
        self.name = entry.name
        self.active = entry.active
        self.visible = entry.visible
        self.isDefault = entry.isDefault
    }
}

struct GraphicPack: Identifiable {
    let normalizedPath: String
    let name: String
    let virtualPath: String
    let description: String
    let version: Int
    var enabled: Bool
    let activated: Bool
    let defaultEnabled: Bool
    let titleIds: [UInt64]
    var presets: [GraphicPackPreset]
    let presetCategories: [String]

    var id: String { normalizedPath }

    var group: String {
        let components = virtualPath.split(separator: "/")
        return components.first.map(String.init) ?? "Other"
    }

    init(_ entry: ObjCGraphicPackEntry) {
        self.normalizedPath = entry.normalizedPath
        self.name = entry.name
        self.virtualPath = entry.virtualPath
        self.description = entry.packDescription
        self.version = Int(entry.version)
        self.enabled = entry.enabled
        self.activated = entry.activated
        self.defaultEnabled = entry.defaultEnabled
        self.titleIds = (entry.titleIds as? [NSNumber])?.map { $0.uint64Value } ?? []
        self.presets = (entry.presets ?? []).map { GraphicPackPreset($0) }
        self.presetCategories = (entry.presetCategories as? [String]) ?? []
    }

    func visiblePresets(for category: String) -> [GraphicPackPreset] {
        presets.filter { $0.visible && $0.category == category }
    }

    func activePreset(for category: String) -> String {
        presets.first(where: { $0.active && $0.category == category })?.name ?? ""
    }
}
