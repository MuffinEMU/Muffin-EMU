import SwiftUI
import MetalKit
#if os(iOS)
import UIKit
#endif

struct MetalViewIOS: UIViewRepresentable {
    var gameManager: GameManager

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else {
            // Honest failure, not a crash - matches this codebase's stated
            // philosophy of surfacing real error states rather than force-unwrapping.
            return view
        }
        view.device = device
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        view.enableSetNeedsDisplay = false

        // Register the render surface right here, immediately, using the screen's
        // own bounds - NOT view.bounds. This view sits in a plain VStack with no
        // explicit .frame(maxWidth:.infinity, maxHeight:.infinity), so UIKit/SwiftUI
        // may never actually lay it out to a nonzero size (or may take an
        // unpredictable number of update cycles to do so) - and since boot() now
        // waits on this registration happening at all, that turned "the boot screen
        // never resolves" into an indefinite hang with zero C++ involvement, not a
        // slow boot. The exact size only matters for M3 (real rendering) later; for
        // now the GPU thread just needs a non-null surface to exist before it starts,
        // so a real (if approximate) screen size beats waiting on layout timing that
        // might never satisfy the old nonzero-bounds check.
        let screenBounds = UIScreen.main.bounds
        gameManager.registerRenderSurface(
            uiView: view,
            width: Int32(screenBounds.width * UIScreen.main.scale),
            height: Int32(screenBounds.height * UIScreen.main.scale),
            dpiScale: Double(UIScreen.main.scale)
        )

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.gameManager = gameManager

        // Fallback: if for some reason makeUIView's registration above didn't take
        // (e.g. this view is somehow recreated after boot already started), retry
        // once real, nonzero view bounds are available. GameManager's surfaceRegistered
        // guard makes this a no-op once registration has already succeeded.
        let bounds = uiView.bounds
        if bounds.width > 0 && bounds.height > 0 {
            gameManager.registerRenderSurface(
                uiView: uiView,
                width: Int32(bounds.width),
                height: Int32(bounds.height),
                dpiScale: Double(uiView.contentScaleFactor)
            )
        }
    }

    func makeCoordinator() -> MetalRenderer {
        return MetalRenderer(gameManager: gameManager)
    }
}

#if os(macOS)
struct MetalView: NSViewRepresentable {
    var gameManager: GameManager

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else {
            return view
        }
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
    private var commandQueue: MTLCommandQueue?

    init(gameManager: GameManager) {
        self.gameManager = gameManager
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let device = view.device else { return }

        if commandQueue == nil {
            commandQueue = device.makeCommandQueue()
        }
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

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
            scale = Float(viewSize.height) / 720.0
        } else {
            scale = Float(viewSize.width) / 1280.0
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
