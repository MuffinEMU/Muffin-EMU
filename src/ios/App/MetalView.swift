import SwiftUI
import MetalKit

struct MetalViewIOS: UIViewRepresentable {
    var gameManager: GameManager

    func makeUIView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice() ?? MTLCreateSystemDefaultDevice()!
        let view = MTKView()
        view.device = device
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        view.enableSetNeedsDisplay = false
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.gameManager = gameManager
    }

    func makeCoordinator() -> MetalRenderer {
        return MetalRenderer(gameManager: gameManager)
    }
}

#if os(macOS)
struct MetalView: NSViewRepresentable {
    var gameManager: GameManager

    func makeNSView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()!
        let view = MTKView()
        view.device = device
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.gameManager = gameManager
    }

    func makeCoordinator() -> MetalRenderer {
        return MetalRenderer(gameManager: gameManager)
    }
}
#endif

class MetalRenderer: NSObject, MTKViewDelegate {
    var gameManager: GameManager

    init(gameManager: GameManager) {
        self.gameManager = gameManager
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let device = view.device else { return }

        guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() else { return }

        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        descriptor.colorAttachments[0].loadAction = .clear

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        if let frameTexture = gameManager.getFrameTexture() {
            let viewSize = view.bounds.size
            renderTextureToScreen(frameTexture, encoder: renderEncoder, viewSize: viewSize, device: device)
        }

        renderEncoder.endEncoding()

        if let drawable = drawable as? CAMetalDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
    }

    private func renderTextureToScreen(_ texture: MTLTexture, encoder: MTLRenderCommandEncoder, viewSize: CGSize, device: MTLDevice) {
        let quad = createScreenQuad(viewSize: viewSize)

        let vertexBuffer = device.makeBuffer(bytes: quad, length: MemoryLayout<Float>.size * quad.count, options: [])

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func createScreenQuad(viewSize: CGSize) -> [Float] {
        let aspectRatio = Float(viewSize.width / viewSize.height)
        let targetAspect: Float = 1280.0 / 720.0

        var quad = [Float]()

        let scale: Float
        if aspectRatio > targetAspect {
            scale = 720.0 / Float(viewSize.height)
        } else {
            scale = 1280.0 / Float(viewSize.width)
        }

        let width = 1280.0 * scale / Float(viewSize.width)
        let height = 720.0 * scale / Float(viewSize.height)

        quad.append(-width)
        quad.append(height)
        quad.append(-width)
        quad.append(-height)
        quad.append(width)
        quad.append(-height)

        quad.append(-width)
        quad.append(height)
        quad.append(width)
        quad.append(-height)
        quad.append(width)
        quad.append(height)

        return quad
    }
}
