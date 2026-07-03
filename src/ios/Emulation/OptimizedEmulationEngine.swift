import Foundation
import MetalKit
import os.log

final class OptimizedEmulationEngine: NSObject, ObservableObject {
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
    private var frameBuffer: MTLTexture?

    private let gpuContext: OptimizedGPUContext
    private let logger = Logger(subsystem: "com.brandon.cemuemulator", category: "EmulationEngine")

    private var instructionCache: [UInt32: UInt32] = [:]
    private let cacheLock = NSLock()

    override init() {
        self.gpuContext = OptimizedGPUContext()
        super.init()
    }

    func loadROM(_ romPath: String) {
        currentRomPath = romPath
        currentGame = URL(fileURLWithPath: romPath).lastPathComponent

        memory = MemoryManager(size: 0x1000_0000)
        cpu = WiiUCPU(memory: memory!)

        loadROMFile(romPath)
        logger.info("ROM loaded: \(self.currentGame)")
    }

    private func loadROMFile(_ path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            logger.error("Failed to load ROM: \(path)")
            return
        }

        guard let memory = memory else { return }

        let romData = [UInt8](data)
        let chunkSize = 1_000_000

        for (index, chunk) in romData.chunked(into: chunkSize).enumerated() {
            let offset = UInt32(index * chunkSize)
            memory.writeBuffer(0x80004000 + offset, buffer: Array(chunk))
        }

        logger.info("ROM data loaded: \(romData.count) bytes")
    }

    func startEmulation() {
        guard memory != nil, cpu != nil else { return }

        isRunning = true
        shouldStop = false

        emulationThread = Thread { [weak self] in
            self?.optimizedEmulationLoop()
        }
        emulationThread?.qualityOfService = .userInteractive
        emulationThread?.start()
    }

    func stopEmulation() {
        shouldStop = true
        isRunning = false
        emulationThread?.cancel()
        instructionCache.removeAll(keepingCapacity: true)
    }

    private func optimizedEmulationLoop() {
        let targetCyclesPerFrame = 68_000_000 / 60
        var accumulatedCycles: UInt64 = 0

        while !shouldStop && isRunning {
            autoreleasepool {
                guard let cpu = cpu else { return }

                let frameCycles = cpu.runUntilFrame()
                accumulatedCycles += UInt64(frameCycles)

                DispatchQueue.main.async { [weak self] in
                    self?.updateFrameRate()
                    self?.renderFrame()
                }

                let sleepTime = max(1, 16_667 - Int(accumulatedCycles * 1000 / 68_000_000))
                usleep(UInt32(sleepTime))

                if accumulatedCycles >= UInt64(targetCyclesPerFrame) {
                    accumulatedCycles = 0
                }
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
            logger.debug("FPS: \(self.frameRate)")
        }
    }

    private func renderFrame() {
        guard let memory = memory else { return }
        frameBuffer = gpuContext.renderOptimizedFrame(memory: memory)
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

class OptimizedGPUContext {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private var renderPipelineState: MTLRenderPipelineState?
    private var framePool: [MTLTexture] = []
    private var currentFrameIndex = 0
    private let framePoolSize = 3

    init() {
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()
        self.commandQueue?.label = "CemuEmulatorCommandQueue"

        setupFramePool()
        setupRenderPipeline()
    }

    private func setupFramePool() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1280,
            height: 720,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .memoryless

        for _ in 0..<framePoolSize {
            if let texture = device.makeTexture(descriptor: descriptor) {
                framePool.append(texture)
            }
        }
    }

    private func setupRenderPipeline() {
        let library = device.makeDefaultLibrary()

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library?.makeFunction(name: "screenVertex")
        pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "screenFragment")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Error creating render pipeline: \(error)")
        }
    }

    func renderOptimizedFrame(memory: MemoryManager) -> MTLTexture? {
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return nil }

        let texture = framePool[currentFrameIndex]
        currentFrameIndex = (currentFrameIndex + 1) % framePoolSize

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return nil
        }

        renderEncoder.setRenderPipelineState(renderPipelineState ?? MTLRenderPipelineState())
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(.back)

        let quad: [Float] = [
            -1.0, 1.0, 0, 1,
            -1.0, -1.0, 0, 0,
            1.0, -1.0, 1, 0,
            -1.0, 1.0, 0, 1,
            1.0, -1.0, 1, 0,
            1.0, 1.0, 1, 1
        ]

        guard let vertexBuffer = device.makeBuffer(bytes: quad, length: MemoryLayout<Float>.size * quad.count, options: .storageModeShared) else {
            return nil
        }

        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        renderEncoder.endEncoding()

        commandBuffer.present(texture)
        commandBuffer.commit()

        return texture
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
