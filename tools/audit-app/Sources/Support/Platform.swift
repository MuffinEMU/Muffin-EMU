//
//  Platform.swift
//  The few places the app touches UIKit, behind one small interface. Everything else in the engine
//  (runner, guest link, log capture) is plain Foundation, which is what lets CI type-check it on a
//  Mac without an iOS SDK.
//
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum Platform {
    struct ScreenInfo {
        var shortPoints: Double
        var longPoints: Double
        var scale: Double
        var isPad: Bool
    }

    static var screen: ScreenInfo {
        #if canImport(UIKit)
        let b = UIScreen.main.bounds
        return ScreenInfo(shortPoints: Double(min(b.width, b.height)), longPoints: Double(max(b.width, b.height)),
                          scale: Double(UIScreen.main.scale), isPad: UIDevice.current.userInterfaceIdiom == .pad)
        #else
        return ScreenInfo(shortPoints: 834, longPoints: 1194, scale: 2, isPad: true)
        #endif
    }

    static var systemName: String {
        #if canImport(UIKit)
        return UIDevice.current.systemName
        #else
        return "macOS"
        #endif
    }

    static var systemVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    /// Keeps the screen awake for the length of a run (a run that stops because the device locked itself says nothing about the core).
    static func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = disabled }
        #endif
    }

    /// `hw.machine`, e.g. "iPad8,11".
    static var machine: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static func thermalStateName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
}
