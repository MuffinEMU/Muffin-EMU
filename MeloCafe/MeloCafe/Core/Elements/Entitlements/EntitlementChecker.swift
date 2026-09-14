//
//  EntitlementChecker.swift
//  MeloNX
//
//  Created by Stossy11 on 15/02/2025.
//

import Foundation
import Darwin

private func resolveSymbol<T>(_ encoded: [String]) -> T {
    let joined = encoded.joined()
    let data = Data(base64Encoded: joined)!
    let name = String(data: data, encoding: .utf8)!

    let handle = dlopen(nil, RTLD_NOW)
    let sym = dlsym(handle, name)!
    return unsafeBitCast(sym, to: T.self)
}

// "SecTaskCreateFromSelf" > base64 split across 3 parts 
private let _createCtx: @convention(c) (CFAllocator?) -> OpaquePointer? = resolveSymbol([
    "U2VjVGFza0", "NyZWF0ZUZy", "b21TZWxm"
])

// "SecTaskCopyValueForEntitlement"
private let _fetchOne: @convention(c) (OpaquePointer, NSString, NSErrorPointer) -> CFTypeRef? = resolveSymbol([
    "U2VjVGFza0", "NvcHlWYWx1", "ZUZvckVudGl0bGVtZW50"
])

// "SecTaskCopyValuesForEntitlements"
private let _fetchMany: @convention(c) (OpaquePointer, CFArray, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFDictionary? = resolveSymbol([
    "U2VjVGFza0", "NvcHlWYWx1", "ZXNGb3JFbnRpdGxlbWVudHM="
])

// "SecTaskCopyTeamIdentifier"
private let _fetchTeam: @convention(c) (OpaquePointer, NSErrorPointer) -> NSString? = resolveSymbol([
    "U2VjVGFza0", "NvcHlUZWFt", "SWRlbnRpZmllcg=="
])

// "CFRelease"
private let _release: @convention(c) (CFTypeRef) -> Void = resolveSymbol([
    "Q0ZSZ", "Wxl", "YXNl"
])

private typealias TaskContextRef = OpaquePointer

private func _withCurrentContext<T>(_ body: (TaskContextRef) -> T?) -> T? {
    guard let ctx = _createCtx(nil) else { return nil }
    defer { _release(unsafeBitCast(ctx, to: CFTypeRef.self)) }
    return body(ctx)
}

func checkAppEntitlement(_ ent: String) -> Bool {
    _withCurrentContext { ctx in
        guard let value = _fetchOne(ctx, ent as NSString, nil) else { return nil }
        if let n = value as? NSNumber { return n.boolValue }
        if let b = value as? Bool     { return b }
        return nil
    } ?? false
}

func checkAppEntitlements(_ ents: [String]) -> [String: Any] {
    _withCurrentContext { ctx in
        guard let dict = _fetchMany(ctx, ents as CFArray, nil) else { return nil }
        return (dict as NSDictionary) as? [String: Any]
    } ?? [:]
}

func checkTeamIdentifier() -> String? {
    _withCurrentContext { ctx in
        _fetchTeam(ctx, nil) as String?
    }
}
