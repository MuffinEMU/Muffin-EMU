// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

//
//  BuildInfo.swift
//  What this build of the Audit app is and which MuffinEMU it was built against. The audit workflow
//  stamps these into Info.plist after the build (the same way the main workflow stamps its version);
//  the app copies them into every report as the build identity.
//
import Foundation

enum BuildInfo {
    static func plist(_ key: String, fallback: String = "unknown") -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: key) as? String, !v.isEmpty { return v }
        return fallback
    }

    static var appVersion: String { plist("CFBundleShortVersionString", fallback: "0") }
    static var appBuild: String { plist("CFBundleVersion", fallback: "0") }

    /// `hooksInfo` is the JSON the core reports about how its audit hooks were compiled.
    static func identity(hooksInfo: String) -> BuildIdentity {
        BuildIdentity(muffinRef: plist("AuditMuffinRef"),
                      muffinSha: plist("AuditMuffinSha"),
                      muffinVersion: plist("AuditMuffinVersion", fallback: ""),
                      coreFingerprint: plist("AuditCoreFingerprint"),
                      hooksBuildInfo: hooksInfo,
                      auditAppVersion: appVersion,
                      auditAppBuild: appBuild,
                      auditToolsSha: plist("AuditToolsSha"),
                      guestBuild: plist("AuditGuestBuild", fallback: "phase1"),
                      workflowRun: plist("AuditWorkflowRun"),
                      builtAt: plist("AuditBuiltAt"))
    }
}
