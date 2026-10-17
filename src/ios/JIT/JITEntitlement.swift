// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// Whether this install carries get-task-allow, which a JIT attach needs. The check
// has to run in the host process (the one being debugged), not the helper, because
// the entitlement belongs to that executable. Uses Security-framework SPI, the same
// way every JIT integration does; it is not App Store material, which is fine for a
// sideloaded build.

import Foundation

enum JITEntitlement {
    // SecTask SPI. Declared here because there is no public header for it.
    private typealias SecTaskCreateFromSelfFn = @convention(c) (CFAllocator?) -> OpaquePointer?
    private typealias SecTaskCopyValueFn = @convention(c) (OpaquePointer?, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFTypeRef>?

    /// True when the host process has `get-task-allow` set. Without it a JIT enabler
    /// cannot attach, so the setup screen tells the user to reinstall with a signing
    /// method that keeps the entitlement.
    static var hasGetTaskAllow: Bool {
        // RTLD_DEFAULT is (void *)-2 on Darwin.
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let createSym = dlsym(rtldDefault, "SecTaskCreateFromSelf"),
              let copySym = dlsym(rtldDefault, "SecTaskCopyValueForEntitlement") else {
            return false
        }
        let createFromSelf = unsafeBitCast(createSym, to: SecTaskCreateFromSelfFn.self)
        let copyValue = unsafeBitCast(copySym, to: SecTaskCopyValueFn.self)

        guard let task = createFromSelf(nil) else { return false }
        guard let valuePtr = copyValue(task, "get-task-allow" as CFString, nil) else { return false }
        let value = valuePtr.takeRetainedValue()
        return (value as? Bool) == true
    }
}
