import Foundation
import GameController
import CoreHaptics
import Combine

/// One physical controller as the Settings list and the core both see it: a stable
/// identity across reconnects isn't available from GameController itself (a GCController
/// carries no persistent id), so this UUID is ours, assigned once per session the
/// controller is seen and kept only in memory - it does not need to survive a relaunch,
/// only a Settings screen re-render.
struct PhysicalControllerEntry: Identifiable {
    let id: UUID
    let name: String
    let hasMotion: Bool
    let hasRumble: Bool
    var controllerType: ControllerType

    fileprivate var device: PhysicalControllerDevice?

    init(id: UUID = UUID(), name: String, hasMotion: Bool, hasRumble: Bool,
         controllerType: ControllerType, device: PhysicalControllerDevice? = nil) {
        self.id = id
        self.name = name
        self.hasMotion = hasMotion
        self.hasRumble = hasRumble
        self.controllerType = controllerType
        self.device = device
    }
}

/// Wraps one GCController and its registration with the core's GCControllerBridge -
/// the multi-controller path CemuBridge.h exposes, distinct from
/// cemu_bridge_set_button_state()/cemu_bridge_set_stick_axis() which the on-screen pad
/// uses. Mirrors MeloCafe's NativeController (Core/Controller/NativeController.swift):
/// same poll-from-the-core-thread design, same context-pointer lifetime handoff to
/// GCBridgeControllerDesc.release, because the core's expectations on the other side of
/// that struct did not change when it was forked.
final class PhysicalControllerDevice {
    let gc: GCController
    private(set) var coreHandle: UnsafeMutableRawPointer?
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?

    // Bumped on every detach so a callback still in flight from the core's poll thread
    // (which holds no lock against Swift tearing this down) can tell it is stale rather
    // than touching a GCController whose delegate was just cleared.
    nonisolated(unsafe) private var generation: UInt64 = 0

    nonisolated private let stateLock = NSLock()
    nonisolated private let motionLock = NSLock()
    nonisolated(unsafe) private var state = GCBridgeControllerState()
    nonisolated(unsafe) private var motion = GCBridgeMotionState()

    private(set) var controllerType: ControllerType = .Pro

    init(gc: GCController) {
        self.gc = gc
        gc.handlerQueue = .main
        setupHaptics()
    }

    deinit {
        detach()
    }

    func detach() {
        gc.extendedGamepad?.valueChangedHandler = nil
        gc.motion?.valueChangedHandler = nil
        if let motion = gc.motion, motion.sensorsRequireManualActivation {
            motion.sensorsActive = false
        }

        stateLock.lock()
        generation &+= 1
        state = GCBridgeControllerState()
        stateLock.unlock()

        motionLock.lock()
        motion = GCBridgeMotionState()
        motionLock.unlock()

        let handle = coreHandle
        coreHandle = nil
        if let handle { GCControllerBridge_remove(handle) }

        stopHaptic()
    }

    /// Registers this controller with the core under `type`, or - if it's already
    /// registered - reassigns its role in place via GCControllerBridge_configure so
    /// switching roles from Settings doesn't drop and re-poll the input source.
    func registerWithCore(_ type: ControllerType) {
        guard type != .MAX else { return }
        controllerType = type

        if let handle = coreHandle {
            GCControllerBridge_configure(handle, type.rawValue)
            return
        }

        guard let pad = gc.extendedGamepad else { return }
        updateState(from: pad)

        let ctx = Unmanaged.passRetained(self).toOpaque()
        var desc = GCBridgeControllerDesc()
        desc.context = ctx
        desc.controllerType = type.rawValue

        desc.poll_state = { ctx in
            let me = Unmanaged<PhysicalControllerDevice>.fromOpaque(ctx!).takeUnretainedValue()
            me.stateLock.lock()
            defer { me.stateLock.unlock() }
            return me.state
        }

        if gc.motion?.hasRotationRate == true {
            desc.poll_motion = { ctx in
                let me = Unmanaged<PhysicalControllerDevice>.fromOpaque(ctx!).takeUnretainedValue()
                me.motionLock.lock()
                defer { me.motionLock.unlock() }
                return me.motion
            }
        }

        if gc.haptics != nil {
            desc.rumble = { ctx, start in PhysicalControllerDevice.rumble(ctx, start) }
        }

        desc.release = { ctx in
            Unmanaged<PhysicalControllerDevice>.fromOpaque(ctx!).release()
        }

        let name = gc.vendorName ?? "MFi Controller"
        name.withCString { ptr in
            desc.display_name = ptr
            coreHandle = GCControllerBridge_add(&desc)
        }

        guard coreHandle != nil else {
            Unmanaged<PhysicalControllerDevice>.fromOpaque(ctx).release()
            return
        }

        let currentGeneration = generation
        gc.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in
            guard let self, self.coreHandle != nil, self.generation == currentGeneration else { return }
            self.updateState(from: pad)
        }

        if let motion = gc.motion, motion.hasRotationRate {
            motion.valueChangedHandler = { [weak self] m in
                guard let self, self.coreHandle != nil, self.generation == currentGeneration else { return }
                self.updateMotion(from: m)
            }
            if motion.sensorsRequireManualActivation {
                motion.sensorsActive = true
            }
        }
    }

    private nonisolated static func rumble(_ ctx: UnsafeMutableRawPointer?, _ start: Bool) {
        let me = Unmanaged<PhysicalControllerDevice>.fromOpaque(ctx!).takeUnretainedValue()
        me.stateLock.lock()
        let generation = me.generation
        me.stateLock.unlock()
        Task { @MainActor in
            guard me.coreHandle != nil, me.generation == generation, me.hapticEngine != nil else { return }
            start ? me.startHaptic() : me.stopHaptic()
        }
    }

    private func updateState(from pad: GCExtendedGamepad) {
        var s = GCBridgeControllerState()
        func bit(_ pressed: Bool, _ bit: Int) { if pressed { s.buttons |= 1 << bit } }
        // Same bit layout the core's GCController.mm expects - see CemuBridge.h's
        // CemuBridgeButton doc comment for why this can't just be handed the touch
        // pad's own enum instead.
        bit(pad.buttonA.isPressed, 0)
        bit(pad.buttonB.isPressed, 1)
        bit(pad.buttonX.isPressed, 2)
        bit(pad.buttonY.isPressed, 3)
        bit(pad.leftShoulder.isPressed, 4)
        bit(pad.rightShoulder.isPressed, 5)
        bit(pad.leftTrigger.isPressed, 6)
        bit(pad.rightTrigger.isPressed, 7)
        bit(pad.buttonOptions?.isPressed ?? false, 8)
        bit(pad.buttonMenu.isPressed, 9)
        bit(pad.leftThumbstickButton?.isPressed ?? false, 10)
        bit(pad.rightThumbstickButton?.isPressed ?? false, 11)
        bit(pad.dpad.up.isPressed, 16)
        bit(pad.dpad.down.isPressed, 17)
        bit(pad.dpad.left.isPressed, 18)
        bit(pad.dpad.right.isPressed, 19)

        s.leftStick = GCBridgeVec2(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
        s.rightStick = GCBridgeVec2(x: pad.rightThumbstick.xAxis.value, y: pad.rightThumbstick.yAxis.value)
        s.leftTrigger = pad.leftTrigger.value
        s.rightTrigger = pad.rightTrigger.value

        stateLock.lock()
        state = s
        stateLock.unlock()
    }

    private func updateMotion(from m: GCMotion) {
        var mo = GCBridgeMotionState()
        let a = SIMD3<Float>(Float(m.acceleration.x), -Float(m.acceleration.y), -Float(m.acceleration.z))
        let g = SIMD3<Float>(Float(m.rotationRate.x), -Float(m.rotationRate.z), Float(m.rotationRate.y))
        mo.accelerometer = GCBridgeVec3(x: a.x, y: a.y, z: a.z)
        mo.gyroscope = GCBridgeVec3(x: g.x, y: g.y, z: g.z)
        mo.orientation = GCBridgeVec3(x: 0, y: 0, z: 0)
        mo.quaternion = GCBridgeQuat(w: 1, x: 0, y: 0, z: 0)
        mo.timestamp = ProcessInfo.processInfo.systemUptime

        motionLock.lock()
        motion = mo
        motionLock.unlock()
    }

    private func setupHaptics() {
        guard let engine = gc.haptics?.createEngine(withLocality: .default) else { return }
        engine.resetHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hapticPlayer = nil
                try? self.hapticEngine?.start()
            }
        }
        try? engine.start()
        hapticEngine = engine
    }

    private func startHaptic() {
        guard let engine = hapticEngine else { return }
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticPlayer = nil
        let params: [CHHapticEventParameter] = [
            .init(parameterID: .hapticIntensity, value: 1.0),
            .init(parameterID: .hapticSharpness, value: 0.5),
        ]
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: params, relativeTime: 0, duration: 1.0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makeAdvancedPlayer(with: pattern) else { return }
        player.loopEnabled = true
        try? player.start(atTime: CHHapticTimeImmediate)
        hapticPlayer = player
    }

    private func stopHaptic() {
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticPlayer = nil
    }
}

/// Detects MFi/Bluetooth controllers via GameController and assigns each a Wii U role,
/// independent of MuffinEMU's own on-screen pad (ControllerPad.swift/MeloControls.swift)
/// which is a completely separate input path and untouched by this file.
///
/// Modeled on MeloCafe's ControllerManager (Core/Controller/ControllerManager.swift),
/// minus the virtual-controller bookkeeping: MuffinEMU's on-screen pad already has its
/// own always-present input path with its own settings, so there is no "virtual
/// controller" entry to fall back to here the way MeloCafe's Melo_Controller-driven one
/// needed. `controllers` is simply empty when nothing physical is connected.
final class PhysicalControllerManager: ObservableObject {
    static let shared = PhysicalControllerManager()

    @Published private(set) var controllers: [PhysicalControllerEntry] = []
    private var observers: [NSObjectProtocol] = []
    private var bridgeActivated = false

    private init() {
        for gc in GCController.controllers() { addNative(gc) }

        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let gc = note.object as? GCController else { return }
            self?.addNative(gc)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let gc = note.object as? GCController else { return }
            guard let index = self.controllers.firstIndex(where: { $0.device?.gc === gc }) else { return }
            self.controllers[index].device?.detach()
            self.controllers.remove(at: index)
        })
    }

    /// Rescans for controllers that connected before this manager was constructed or
    /// while the app was backgrounded. GameController's own notifications cover the
    /// normal case; this exists for the same reason
    /// cemu_bridge_refresh_input_devices() does on the legacy single-controller path -
    /// cheap, and closes any window where a connect notification was missed.
    func rescan() {
        let connected = Set(GCController.controllers().map(ObjectIdentifier.init))
        for entry in controllers where entry.device.map({ !connected.contains(ObjectIdentifier($0.gc)) }) ?? false {
            entry.device?.detach()
        }
        controllers.removeAll { entry in
            guard let device = entry.device else { return true }
            return !connected.contains(ObjectIdentifier(device.gc))
        }
        for gc in GCController.controllers() { addNative(gc) }
    }

    func canSelectType(_ type: ControllerType, for id: UUID) -> Bool {
        guard type != .MAX else { return false }
        let others = controllers.filter { $0.id != id }
        // The Wii U takes exactly one GamePad; Pro Controllers/Classic Controllers/
        // Wiimotes can stack up to the usual four extra player slots. This isn't
        // enforced by the core (GCControllerBridge_add only rejects a bad enum value),
        // so the UI is what keeps a second GamePad from ever being offered.
        if type == .VPAD {
            return !others.contains { $0.controllerType == .VPAD }
        }
        return others.filter { $0.controllerType != .VPAD }.count < 4
    }

    func setControllerType(id: UUID, to type: ControllerType) {
        guard canSelectType(type, for: id),
              let index = controllers.firstIndex(where: { $0.id == id }) else { return }
        controllers[index].controllerType = type
        controllers[index].device?.registerWithCore(type)
        syncOrder()
    }

    func remove(id: UUID) {
        guard let index = controllers.firstIndex(where: { $0.id == id }) else { return }
        controllers[index].device?.detach()
        controllers.remove(at: index)
    }

    func move(from source: IndexSet, to destination: Int) {
        controllers.move(fromOffsets: source, toOffset: destination)
        syncOrder()
    }

    private func addNative(_ gc: GCController) {
        guard gc.extendedGamepad != nil,
              !controllers.contains(where: { $0.device?.gc === gc }) else { return }

        activateBridgeIfNeeded()

        let type: ControllerType = controllers.contains { $0.controllerType == .VPAD } ? .Pro : .VPAD
        let device = PhysicalControllerDevice(gc: gc)
        let entry = PhysicalControllerEntry(
            name: gc.vendorName ?? "Controller",
            hasMotion: gc.motion?.hasRotationRate == true,
            hasRumble: gc.haptics != nil,
            controllerType: type,
            device: device
        )
        controllers.append(entry)
        device.registerWithCore(type)
        syncOrder()
    }

    /// Steps the legacy single-implicit-controller merge (CemuBridge.mm's
    /// ios_bind_first_controller) aside, once, the first time a physical controller is
    /// actually seen. Deferred to here rather than done unconditionally in init() so a
    /// device with no MFi controller ever attached never touches the legacy path at
    /// all, and the on-screen pad's physical-controller merge behaves exactly as before
    /// until this manager has something of its own to manage.
    private func activateBridgeIfNeeded() {
        guard !bridgeActivated else { return }
        bridgeActivated = true
        cemu_bridge_set_physical_controller_bridge_active(true)
    }

    private func syncOrder() {
        var handles = controllers.compactMap { $0.device?.coreHandle }.map { Optional($0) }
        handles.withUnsafeMutableBufferPointer { buffer in
            GCControllerBridge_setOrder(buffer.baseAddress, buffer.count)
        }
        GCControllerBridge_notifyChanged()
    }
}
