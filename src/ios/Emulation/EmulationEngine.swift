import Foundation
import MetalKit

class EmulationEngine: NSObject, ObservableObject {
    @Published var isRunning: Bool = false
    @Published var frameRate: Int = 0
    @Published var currentGame: String = ""

    private var cpu: WiiUCPU?
    private var memory: MemoryManager?
    private var currentRomPath: String = ""
    private var emulationThread: Thread?
    private var shouldStop: Bool = false
    private var frameCount: Int = 0
    private var lastFPSUpdate: Date = Date()

    private let gpuContext: GPUContext
    private var frameBuffer: MTLTexture?

    override init() {
        self.gpuContext = GPUContext()
        super.init()
    }

    func loadROM(_ romPath: String) {
        currentRomPath = romPath
        currentGame = URL(fileURLWithPath: romPath).lastPathComponent

        memory = MemoryManager(size: 0x2000_0000)
        cpu = WiiUCPU(memory: memory!)

        loadROMFile(romPath)
    }

    private func loadROMFile(_ path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("Failed to load ROM: \(path)")
            return
        }

        guard let memory = memory else { return }

        let romData = [UInt8](data)
        memory.writeBuffer(0x80004000, buffer: romData)
    }

    func startEmulation() {
        guard memory != nil, cpu != nil else { return }

        isRunning = true
        shouldStop = false

        emulationThread = Thread { [weak self] in
            self?.emulationLoop()
        }
        emulationThread?.start()
    }

    func stopEmulation() {
        shouldStop = true
        isRunning = false
        emulationThread?.cancel()
    }

    private func emulationLoop() {
        while !shouldStop && isRunning {
            autoreleasepool {
                guard let cpu = cpu else { return }

                cpu.runUntilFrame()

                DispatchQueue.main.async { [weak self] in
                    self?.updateFrameRate()
                    self?.renderFrame()
                }

                usleep(16_667)
            }
        }
    }

    private func updateFrameRate() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)

        if elapsed >= 1.0 {
            frameRate = frameCount
            frameCount = 0
            lastFPSUpdate = now
        }
    }

    private func renderFrame() {
        guard let memory = memory else { return }

        frameBuffer = gpuContext.renderFrame(memory: memory)
    }

    func getFrameTexture() -> MTLTexture? {
        return frameBuffer
    }

    func getState() -> CPUState? {
        return cpu?.getState()
    }

    func reset() {
        stopEmulation()
        memory?.reset()
        frameCount = 0
        frameRate = 0
    }

    deinit {
        stopEmulation()
    }
}

class GPUContext {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private let library: MTLLibrary?

    init() {
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()
        self.library = device.makeDefaultLibrary()
    }

    func renderFrame(memory: MemoryManager) -> MTLTexture? {
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return nil }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.width = 1280
        descriptor.height = 720
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return nil }

        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(.back)
        renderEncoder.endEncoding()

        commandBuffer.present(texture)
        commandBuffer.commit()

        return texture
    }
}
