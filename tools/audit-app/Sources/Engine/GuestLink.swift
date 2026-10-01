//
//  GuestLink.swift
//  The mailbox half of the probe protocol: reads what the guest publishes and sends it commands,
//  through the core's guest-memory hooks. The layout mirrors tools/audit-app/guest/audit_protocol.h;
//  tools/audit-app/check_protocol.py fails CI if the two disagree.
//
import Foundation

enum Mailbox {
    static let magic: UInt32 = 0x4D41_5544 // 'MAUD'
    static let size: UInt32 = 0x200

    // guest -> host
    static let offMagic: UInt32 = 0x000
    static let offVersion: UInt32 = 0x004
    static let offGuestState: UInt32 = 0x008
    static let offGuestSeq: UInt32 = 0x00C
    static let offFrames: UInt32 = 0x010
    static let offRunToken: UInt32 = 0x014
    static let offCheckpointSeq: UInt32 = 0x018
    static let offTestResult: UInt32 = 0x01C
    static let offChecksum: UInt32 = 0x020
    static let offGuestErrors: UInt32 = 0x024
    static let offPingEcho: UInt32 = 0x028
    static let offAckSeq: UInt32 = 0x02C
    static let offInputHold: UInt32 = 0x030
    static let offInputLX: UInt32 = 0x034
    static let offInputLY: UInt32 = 0x038
    static let offInputRX: UInt32 = 0x03C
    static let offInputRY: UInt32 = 0x040
    static let offTouchState: UInt32 = 0x044
    static let offTouchX: UInt32 = 0x048
    static let offTouchY: UInt32 = 0x04C
    static let offInputReads: UInt32 = 0x050
    static let offInputChanges: UInt32 = 0x054
    static let offInputError: UInt32 = 0x058
    static let offAudioState: UInt32 = 0x05C
    static let offAudioStep: UInt32 = 0x060
    static let offCheckpointName: UInt32 = 0x080
    static let offTestId: UInt32 = 0x0B0
    static let offMessage: UInt32 = 0x0E0
    // host -> guest
    static let offCmd: UInt32 = 0x100
    static let offCmdSeq: UInt32 = 0x104
    static let offCmdRunToken: UInt32 = 0x108
    static let offCmdDurationMs: UInt32 = 0x10C
    static let offCmdSeed: UInt32 = 0x110
    static let offHostFlags: UInt32 = 0x114
    static let offCmdTestId: UInt32 = 0x120
    static let offCmdParams: UInt32 = 0x150

    static let nameLen: Int = 48
    static let messageLen: Int = 96
    static let paramsLen: Int = 128

    // values
    static let stateBoot: UInt32 = 0
    static let stateIdle: UInt32 = 1
    static let stateRunning: UInt32 = 2
    static let stateCheckpoint: UInt32 = 3
    static let stateFatal: UInt32 = 4

    static let cmdNone: UInt32 = 0
    static let cmdRun: UInt32 = 1
    static let cmdContinue: UInt32 = 2
    static let cmdAbort: UInt32 = 3
    static let cmdExit: UInt32 = 4
    static let cmdPing: UInt32 = 5

    static let resultNone: UInt32 = 0
    static let resultOK: UInt32 = 1
    static let resultError: UInt32 = 2
    static let resultAborted: UInt32 = 3
    static let resultUnknown: UInt32 = 4

    static let protocolVersion: UInt32 = 1
}

/// Everything the guest publishes, read in one go.
struct GuestState {
    var magic: UInt32 = 0
    var version: UInt32 = 0
    var state: UInt32 = 0
    var seq: UInt32 = 0
    var frames: UInt32 = 0
    var runToken: UInt32 = 0
    var checkpointSeq: UInt32 = 0
    var testResult: UInt32 = 0
    var checksum: UInt32 = 0
    var errors: UInt32 = 0
    var pingEcho: UInt32 = 0
    var ackSeq: UInt32 = 0
    var inputHold: UInt32 = 0
    var leftX: Int32 = 0
    var leftY: Int32 = 0
    var rightX: Int32 = 0
    var rightY: Int32 = 0
    var touchState: UInt32 = 0
    var touchX: UInt32 = 0
    var touchY: UInt32 = 0
    var inputReads: UInt32 = 0
    var inputChanges: UInt32 = 0
    var inputError: UInt32 = 0
    var audioState: UInt32 = 0
    var audioStep: UInt32 = 0
    var checkpointName: String = ""
    var testId: String = ""
    var message: String = ""

    var resultName: String {
        switch testResult {
        case Mailbox.resultOK: return "ok"
        case Mailbox.resultError: return "error"
        case Mailbox.resultAborted: return "aborted"
        case Mailbox.resultUnknown: return "unknown-test"
        default: return "none"
        }
    }
}

/// Reads and writes the guest's mailbox. Every access goes through the core's guest-memory hooks, which
/// refuse anything outside the guest's data range and answer false while no title runs.
final class GuestLink {
    private(set) var base: UInt32 = 0
    private var hostSeq: UInt32 = 0

    var isAttached: Bool { base != 0 }

    func attach(address: UInt32) {
        base = address
        hostSeq = readWord(Mailbox.offCmdSeq) ?? 0
    }

    func detach() {
        base = 0
        hostSeq = 0
    }

    // MARK: Reads

    func readWord(_ offset: UInt32) -> UInt32? {
        guard base != 0 else { return nil }
        var be: UInt32 = 0
        guard cemu_audit_guest_read(base + offset, &be, 4) else { return nil }
        return UInt32(bigEndian: be)
    }

    /// True when the magic word is in place, which the guest writes last during its start-up.
    func isValid() -> Bool {
        readWord(Mailbox.offMagic) == Mailbox.magic && readWord(Mailbox.offVersion) == Mailbox.protocolVersion
    }

    func readState() -> GuestState? {
        guard base != 0 else { return nil }
        var raw = [UInt8](repeating: 0, count: Int(Mailbox.size))
        let ok = raw.withUnsafeMutableBytes { cemu_audit_guest_read(base, $0.baseAddress, Mailbox.size) }
        guard ok else { return nil }

        func word(_ off: UInt32) -> UInt32 {
            let i = Int(off)
            return UInt32(raw[i]) << 24 | UInt32(raw[i + 1]) << 16 | UInt32(raw[i + 2]) << 8 | UInt32(raw[i + 3])
        }
        func str(_ off: UInt32, _ cap: Int) -> String {
            let slice = raw[Int(off)..<(Int(off) + cap)]
            let end = slice.firstIndex(of: 0) ?? slice.endIndex
            return String(decoding: raw[Int(off)..<end], as: UTF8.self)
        }

        var s = GuestState()
        s.magic = word(Mailbox.offMagic)
        s.version = word(Mailbox.offVersion)
        s.state = word(Mailbox.offGuestState)
        s.seq = word(Mailbox.offGuestSeq)
        s.frames = word(Mailbox.offFrames)
        s.runToken = word(Mailbox.offRunToken)
        s.checkpointSeq = word(Mailbox.offCheckpointSeq)
        s.testResult = word(Mailbox.offTestResult)
        s.checksum = word(Mailbox.offChecksum)
        s.errors = word(Mailbox.offGuestErrors)
        s.pingEcho = word(Mailbox.offPingEcho)
        s.ackSeq = word(Mailbox.offAckSeq)
        s.inputHold = word(Mailbox.offInputHold)
        s.leftX = Int32(bitPattern: word(Mailbox.offInputLX))
        s.leftY = Int32(bitPattern: word(Mailbox.offInputLY))
        s.rightX = Int32(bitPattern: word(Mailbox.offInputRX))
        s.rightY = Int32(bitPattern: word(Mailbox.offInputRY))
        s.touchState = word(Mailbox.offTouchState)
        s.touchX = word(Mailbox.offTouchX)
        s.touchY = word(Mailbox.offTouchY)
        s.inputReads = word(Mailbox.offInputReads)
        s.inputChanges = word(Mailbox.offInputChanges)
        s.inputError = word(Mailbox.offInputError)
        s.audioState = word(Mailbox.offAudioState)
        s.audioStep = word(Mailbox.offAudioStep)
        s.checkpointName = str(Mailbox.offCheckpointName, Mailbox.nameLen)
        s.testId = str(Mailbox.offTestId, Mailbox.nameLen)
        s.message = str(Mailbox.offMessage, Mailbox.messageLen)
        return s
    }

    // MARK: Writes

    @discardableResult
    private func writeWord(_ offset: UInt32, _ value: UInt32) -> Bool {
        guard base != 0 else { return false }
        var be = value.bigEndian
        return cemu_audit_guest_write(base + offset, &be, 4)
    }

    @discardableResult
    private func writeString(_ offset: UInt32, _ cap: Int, _ text: String) -> Bool {
        guard base != 0 else { return false }
        var bytes = Array(text.utf8.prefix(cap - 1))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: cap - bytes.count))
        return bytes.withUnsafeBytes { cemu_audit_guest_write(base + offset, $0.baseAddress, UInt32(cap)) }
    }

    /// Publishes a command. The payload goes first and the sequence number last, so the guest never acts on a half-written command.
    @discardableResult
    func send(command: UInt32, testId: String = "", params: String = "", runToken: UInt32 = 0, durationMs: UInt32 = 0, seed: UInt32 = 0) -> Bool {
        guard base != 0 else { return false }
        var ok = true
        if command == Mailbox.cmdRun {
            ok = ok && writeString(Mailbox.offCmdTestId, Mailbox.nameLen, testId)
            ok = ok && writeString(Mailbox.offCmdParams, Mailbox.paramsLen, params)
            ok = ok && writeWord(Mailbox.offCmdRunToken, runToken)
            ok = ok && writeWord(Mailbox.offCmdDurationMs, durationMs)
            ok = ok && writeWord(Mailbox.offCmdSeed, seed)
        }
        ok = ok && writeWord(Mailbox.offCmd, command)
        hostSeq &+= 1
        ok = ok && writeWord(Mailbox.offCmdSeq, hostSeq)
        return ok
    }

    func setHostFlags(captureWorking: Bool, padSurface: Bool) {
        writeWord(Mailbox.offHostFlags, (captureWorking ? 1 : 0) | (padSurface ? 2 : 0))
    }

    /// True once the guest has consumed the last command.
    func lastCommandAcknowledged() -> Bool {
        guard let ack = readWord(Mailbox.offAckSeq) else { return false }
        return ack == hostSeq
    }
}
