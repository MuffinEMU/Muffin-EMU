import Foundation
#if os(iOS)
import UIKit
#endif

/// What this device is and what it can afford, read once at launch from the engine's
/// capability snapshot (`CemuDeviceCaps.h`, `Common/DeviceCapabilities.h`). Every device
/// dependent default in the app reads it from here instead of carrying a number that was
/// measured on one device.
///
/// The standard tier (4.5 to 7 GiB of RAM: 6 GB iPads and iPhone 14 to 16) gets the
/// values the app shipped with, so nothing that works on those devices changes. Devices with
/// less memory get conservative defaults; devices with more, and the newest chips, get more.
struct DeviceCapabilities {

    enum Tier: Int {
        case low = 0, standard = 1, high = 2
        var name: String { self == .low ? "low" : (self == .high ? "high" : "standard") }
    }

    enum ScreenClass: Int {
        case unknown = 0, phoneCompact = 1, phone = 2, pad = 3, padLarge = 4
        var isPhone: Bool { self == .phoneCompact || self == .phone }
    }

    let raw: CemuDeviceCaps
    /// hw.machine, e.g. "iPhone17,1".
    let machine: String
    /// From the GPU name, e.g. "A12Z", "A17 Pro", "M4"; empty if the GPU did not say.
    let chip: String
    /// The line every device log starts with.
    let line: String

    var tier: Tier { Tier(rawValue: Int(raw.tier)) ?? .standard }
    var screenClass: ScreenClass { ScreenClass(rawValue: Int(raw.screenClass)) ?? .unknown }
    var isPhone: Bool { !raw.isPad }
    var isHighEndSoC: Bool { raw.isHighEndSoc }
    /// Whether three host threads for the emulated cores are worth offering at all.
    var multicoreViable: Bool { raw.multicoreViable }
    /// Most host threads the emulated cores may use here, 1 to 3. A CPU cores option is listed only up to this.
    var maxHostThreads: Int { Int(raw.maxHostThreads) }
    var performanceCores: Int { Int(raw.perfCores) }
    var meshShaders: Bool { raw.meshShaders }
    /// What Settings says when `multicoreViable` is false. Auto stays on one core there, and
    /// Basic offers nothing else; Advanced can still force a mode (ios_decide_core_count in CemuBridge.mm).
    static let oneCoreOnlyText = "One core only: this device has too little memory or too few performance cores to run more than one at once."

    /// A17 Pro or later, or any M-series chip, with 7 GiB or more: the GPU and thermal room to start
    /// Resolution at High. `RenderScale.deviceDefault` is the one place the default is decided, and
    /// this is the capability it reads.
    var startsAtHighRenderScale: Bool { raw.isHighEndSoc && tier == .high }

    /// The snapshot. Taken on first use; `bootstrap()` makes that the first thing the app does.
    static let current: DeviceCapabilities = {
        #if os(iOS)
        let bounds = UIScreen.main.bounds
        cemu_device_caps_set_screen(
            Double(min(bounds.width, bounds.height)),
            Double(max(bounds.width, bounds.height)),
            Double(UIScreen.main.nativeScale),
            UIDevice.current.userInterfaceIdiom == .pad)
        #endif
        cemu_device_caps_initialize()
        var caps = CemuDeviceCaps()
        cemu_device_caps_get(&caps)
        return DeviceCapabilities(
            raw: caps,
            machine: String(cString: cemu_device_caps_machine()),
            chip: String(cString: cemu_device_caps_chip()),
            line: String(cString: cemu_device_caps_line()))
    }()

    /// Call first thing at launch: takes the snapshot and writes its one-line summary as the
    /// first line of the crash log and the launch log.
    static func bootstrap() {
        cemu_bridge_log_checkpoint(current.line)
    }
}
