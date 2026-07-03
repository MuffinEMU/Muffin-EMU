import Foundation

class MemoryManager {
    private var memory: [UInt8]
    private let memorySize: Int
    private let mmioHandlers: NSMutableDictionary

    init(size: Int = 0x2000_0000) {
        self.memorySize = size
        self.memory = Array(repeating: 0, count: size)
        self.mmioHandlers = NSMutableDictionary()
        setupMemoryMap()
    }

    private func setupMemoryMap() {
        let wiiBoundary = 0x8200_0000
        let gpuBase = 0x0C00_0000
        let ioBase = 0x0D00_0000

        registerMMIOHandler(range: gpuBase..<(gpuBase + 0x200_0000), name: "GPU")
        registerMMIOHandler(range: ioBase..<(ioBase + 0x200_0000), name: "IO")
    }

    private func registerMMIOHandler(range: Range<Int>, name: String) {
        mmioHandlers[name] = MMIOHandler(range: range, name: name)
    }

    func read8(_ address: UInt32) -> UInt8 {
        let addr = Int(address)
        if addr >= memorySize { return 0 }
        return memory[addr]
    }

    func read16(_ address: UInt32) -> UInt16 {
        let addr = Int(address)
        if addr >= memorySize - 1 { return 0 }
        let low = UInt16(memory[addr])
        let high = UInt16(memory[addr + 1])
        return (high << 8) | low
    }

    func read32(_ address: UInt32) -> UInt32 {
        let addr = Int(address)
        if addr >= memorySize - 3 { return 0 }

        if let handler = findMMIOHandler(for: addr) {
            return handler.read32(addr)
        }

        let b0 = UInt32(memory[addr])
        let b1 = UInt32(memory[addr + 1])
        let b2 = UInt32(memory[addr + 2])
        let b3 = UInt32(memory[addr + 3])
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    }

    func read64(_ address: UInt32) -> UInt64 {
        let addr = Int(address)
        if addr >= memorySize - 7 { return 0 }
        let low = read32(address)
        let high = read32(address + 4)
        return (UInt64(high) << 32) | UInt64(low)
    }

    func readBuffer(_ address: UInt32, length: Int) -> [UInt8] {
        let addr = Int(address)
        guard addr >= 0, addr + length <= memorySize else { return [] }
        return Array(memory[addr..<(addr + length)])
    }

    func write8(_ address: UInt32, _ value: UInt8) {
        let addr = Int(address)
        if addr >= 0 && addr < memorySize {
            memory[addr] = value
        }
    }

    func write16(_ address: UInt32, _ value: UInt16) {
        let addr = Int(address)
        if addr >= 0 && addr + 1 < memorySize {
            memory[addr] = UInt8(value & 0xFF)
            memory[addr + 1] = UInt8((value >> 8) & 0xFF)
        }
    }

    func write32(_ address: UInt32, _ value: UInt32) {
        let addr = Int(address)
        if addr >= 0 && addr + 3 < memorySize {
            if let handler = findMMIOHandler(for: addr) {
                handler.write32(addr, value)
                return
            }

            memory[addr] = UInt8(value & 0xFF)
            memory[addr + 1] = UInt8((value >> 8) & 0xFF)
            memory[addr + 2] = UInt8((value >> 16) & 0xFF)
            memory[addr + 3] = UInt8((value >> 24) & 0xFF)
        }
    }

    func write64(_ address: UInt32, _ value: UInt64) {
        write32(address, UInt32(value & 0xFFFFFFFF))
        write32(address + 4, UInt32((value >> 32) & 0xFFFFFFFF))
    }

    func writeBuffer(_ address: UInt32, buffer: [UInt8]) {
        let addr = Int(address)
        guard addr >= 0, addr + buffer.count <= memorySize else { return }
        memory.replaceSubrange(addr..<(addr + buffer.count), with: buffer)
    }

    private func findMMIOHandler(for address: Int) -> MMIOHandler? {
        for handler in mmioHandlers.allValues {
            if let h = handler as? MMIOHandler, h.range.contains(address) {
                return h
            }
        }
        return nil
    }

    func reset() {
        memory = Array(repeating: 0, count: memorySize)
    }

    func getMemorySize() -> Int {
        return memorySize
    }
}

class MMIOHandler {
    let range: Range<Int>
    let name: String

    init(range: Range<Int>, name: String) {
        self.range = range
        self.name = name
    }

    func read8(_ address: Int) -> UInt8 { 0 }
    func read16(_ address: Int) -> UInt16 { 0 }
    func read32(_ address: Int) -> UInt32 { 0 }

    func write8(_ address: Int, _ value: UInt8) {}
    func write16(_ address: Int, _ value: UInt16) {}
    func write32(_ address: Int, _ value: UInt32) {}
}
