import Foundation

class WiiUCPU {
    private var registers: [UInt32] = Array(repeating: 0, count: 32)
    private var floatingPointRegisters: [Double] = Array(repeating: 0, count: 32)
    private var pc: UInt32 = 0x80004000
    private var lr: UInt32 = 0
    private var ctr: UInt32 = 0
    private var cr: UInt32 = 0

    private let memory: MemoryManager
    private var cycleCount: UInt64 = 0
    private var instructionCount: UInt64 = 0

    init(memory: MemoryManager) {
        self.memory = memory
        self.pc = 0x80004000
    }

    func executeInstruction() -> UInt32 {
        let opcode = memory.read32(pc)

        let primaryOpcode = (opcode >> 26) & 0x3F
        let instruction = PPCInstruction(opcode: opcode)

        let cyclesTaken = execute(instruction)
        pc = pc &+ 4
        cycleCount += UInt64(cyclesTaken)
        instructionCount += 1

        return cyclesTaken
    }

    private func execute(_ instr: PPCInstruction) -> UInt32 {
        switch instr.primaryOpcode {
        case 0x03: return executeIllegal(instr)
        case 0x07: return executeMULLI(instr)
        case 0x08: return executeSUBFIC(instr)
        case 0x0C: return executeADDIC(instr)
        case 0x0D: return executeADDIC_(instr)
        case 0x0E: return executeADDI(instr)
        case 0x0F: return executeADDIS(instr)
        case 0x10: return executeBCx(instr)
        case 0x12: return executeB(instr)
        case 0x13: return executeBCxL(instr)
        case 0x14: return executeRLWINM(instr)
        case 0x15: return executeRLWINM_(instr)
        case 0x16: return executeRLWIMI(instr)
        case 0x17: return executeRLWIMI_(instr)
        case 0x18: return executeORI(instr)
        case 0x19: return executeORIS(instr)
        case 0x1A: return executeXORI(instr)
        case 0x1B: return executeXORIS(instr)
        case 0x1C: return executeANDI_(instr)
        case 0x1D: return executeANDIS_(instr)
        case 0x1E: return executePrimaryOpcode30(instr)
        case 0x1F: return executePrimaryOpcode31(instr)
        case 0x20...0x23: return executeLWZ(instr)
        case 0x24...0x25: return executeLFD(instr)
        case 0x28...0x2B: return executeSTW(instr)
        case 0x2C...0x2D: return executeSTFD(instr)
        default: return 1
        }
    }

    private func executeIllegal(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeMULLI(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeSUBFIC(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeADDIC(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeADDIC_(_ instr: PPCInstruction) -> UInt32 { 1 }

    private func executeADDI(_ instr: PPCInstruction) -> UInt32 {
        let rt = instr.rt
        let ra = instr.ra == 0 ? UInt32(0) : registers[Int(instr.ra)]
        let simm = instr.simm
        registers[Int(rt)] = ra &+ simm
        return 1
    }

    private func executeADDIS(_ instr: PPCInstruction) -> UInt32 {
        let rt = instr.rt
        let ra = instr.ra == 0 ? UInt32(0) : registers[Int(instr.ra)]
        let simm = instr.simm << 16
        registers[Int(rt)] = ra &+ simm
        return 1
    }

    private func executeBCx(_ instr: PPCInstruction) -> UInt32 {
        let bo = instr.bo
        let bi = instr.bi
        let bd = instr.bd
        let taken = evaluateBranchCondition(bo, bi)
        if taken {
            pc = pc &+ (Int32(bitPattern: bd << 2) >= 0 ? UInt32(bitPattern: Int32(bitPattern: bd) << 2) : UInt32(bitPattern: Int32(bitPattern: bd) << 2))
        }
        return 1
    }

    private func executeB(_ instr: PPCInstruction) -> UInt32 {
        let li = instr.li
        pc = UInt32(bitPattern: Int32(bitPattern: li) << 2)
        return 1
    }

    private func executeBCxL(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeRLWINM(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeRLWINM_(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeRLWIMI(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeRLWIMI_(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeORI(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeORIS(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeXORI(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeXORIS(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeANDI_(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executeANDIS_(_ instr: PPCInstruction) -> UInt32 { 1 }

    private func executePrimaryOpcode30(_ instr: PPCInstruction) -> UInt32 { 1 }
    private func executePrimaryOpcode31(_ instr: PPCInstruction) -> UInt32 { 1 }

    private func executeLWZ(_ instr: PPCInstruction) -> UInt32 {
        let rt = instr.rt
        let ra = instr.ra == 0 ? UInt32(0) : registers[Int(instr.ra)]
        let d = instr.simm
        let address = ra &+ d
        registers[Int(rt)] = memory.read32(address)
        return 1
    }

    private func executeLFD(_ instr: PPCInstruction) -> UInt32 {
        let ft = instr.rt
        let ra = instr.ra == 0 ? UInt32(0) : registers[Int(instr.ra)]
        let d = instr.simm
        let address = ra &+ d
        let value = memory.read64(address)
        floatingPointRegisters[Int(ft)] = Double(bitPattern: value)
        return 1
    }

    private func executeSTW(_ instr: PPCInstruction) -> UInt32 {
        let rs = instr.rt
        let ra = instr.ra == 0 ? UInt32(0) : registers[Int(instr.ra)]
        let d = instr.simm
        let address = ra &+ d
        memory.write32(address, registers[Int(rs)])
        return 1
    }

    private func executeSTFD(_ instr: PPCInstruction) -> UInt32 {
        let fs = instr.rt
        let ra = instr.ra == 0 ? UInt32(0) : registers[Int(instr.ra)]
        let d = instr.simm
        let address = ra &+ d
        memory.write64(address, floatingPointRegisters[Int(fs)].bitPattern)
        return 1
    }

    private func evaluateBranchCondition(_ bo: UInt32, _ bi: UInt32) -> Bool {
        return (bo & 0x10) != 0
    }

    func step(_ count: UInt32 = 1) {
        for _ in 0..<count {
            _ = executeInstruction()
        }
    }

    func runUntilFrame() -> UInt64 {
        let targetCycles = cycleCount + (68_000_000 / 60)
        while cycleCount < targetCycles {
            _ = executeInstruction()
        }
        return cycleCount
    }

    func getState() -> CPUState {
        return CPUState(
            pc: pc,
            registers: registers,
            fpRegisters: floatingPointRegisters,
            cycleCount: cycleCount,
            instructionCount: instructionCount
        )
    }
}

struct PPCInstruction {
    let opcode: UInt32

    var primaryOpcode: UInt32 { (opcode >> 26) & 0x3F }
    var rt: UInt32 { (opcode >> 21) & 0x1F }
    var ra: UInt32 { (opcode >> 16) & 0x1F }
    var rb: UInt32 { (opcode >> 11) & 0x1F }
    var simm: UInt32 { UInt32(bitPattern: Int32(bitPattern: opcode & 0xFFFF)) }
    var uimm: UInt32 { opcode & 0xFFFF }
    var bo: UInt32 { (opcode >> 21) & 0x1F }
    var bi: UInt32 { (opcode >> 16) & 0x1F }
    var bd: UInt32 { opcode & 0xFFFF }
    var li: UInt32 { opcode & 0x3FFFFF }
}

struct CPUState {
    let pc: UInt32
    let registers: [UInt32]
    let fpRegisters: [Double]
    let cycleCount: UInt64
    let instructionCount: UInt64
}
