import SwiftUI
import MetalKit
#if os(iOS)
import UIKit
#endif

/// Plain `UIView` has no hook that fires when its own bounds change - UIKit posts no
/// "bounds changed" notification, and SwiftUI only calls `updateUIView` in response to
/// state changes, not layout passes - so without this override `DisplayRouter` had no
/// way to learn that the container it was handed had settled into a new size, and the
/// TV/pad `CAMetalLayer` sublayers (and the C++-side geometry `WindowSystem` keeps for
/// them) kept whatever size they were given at registration time for the rest of the
/// session, even through a rotation or (`UIRequiresFullScreen` is not set in
/// `project.yml`, so this is a real, reachable case) an iPad Split View/Slide Over
/// resize. `layoutSubviews()` is the one hook UIKit reliably calls whenever this
/// view's own bounds actually change, regardless of what drove the change.
final class DeviceContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        DisplayRouter.shared.deviceContainerDidLayout(self)
    }
}

struct MetalViewIOS: UIViewRepresentable {
    var gameManager: GameManager

    // This returns a plain CONTAINER view; the view the C++ renderer actually draws
    // into is DisplayRouter.shared.tvRenderView, added as a subview of it. The
    // indirection is what makes the Wii U TV screen movable between this device and an
    // external display without destroying its CAMetalLayer: SwiftUI only ever sees the
    // container, so it can create, lay out and tear that down as it likes, while the
    // render view - and the layer the GPU thread holds a bare pointer to - is reparented
    // by DisplayRouter and outlives all of it.
    //
    // Neither is an MTKView, deliberately. MTKView overrides +layerClass to make its OWN
    // .layer a CAMetalLayer with its own active render loop. CreateMetalLayer()
    // (MetalLayer.mm) then added the REAL C++ renderer's CAMetalLayer as a SUBLAYER of
    // that already-active Metal-backed layer - two independent Metal render loops
    // fighting over one layer tree, one requesting drawables via MTKView's own
    // currentDrawable every frame, the other calling nextDrawable() directly on the
    // sublayer from the GPU thread. A live device test confirmed this is genuinely
    // unstable (crashes recurring in MetalRenderer::BeginFrame -> nextDrawable even
    // after fixing the separate view-retain issue) - a plain UIView's .layer is an
    // ordinary CALayer with no competing rendering machinery of its own, so the C++
    // sublayer has the view's layer tree to itself.
    func makeUIView(context: Context) -> UIView {
        let container = DeviceContainerView()
        container.backgroundColor = .black

        // Arm display detection before anything is registered, so a TV that is already
        // connected at launch and one plugged in later take the same code path. The
        // router decides where the Wii U TV screen goes, registers the surface (which is
        // what starts the boot - see GameManager.registerRenderSurface), and creates a
        // GamePad surface only when there is a second display to put it on.
        DisplayRouter.shared.startObserving()
        DisplayRouter.shared.attach(deviceContainer: container)
        DisplayRouter.shared.registerSurfaces(with: gameManager)

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Fallback: if for some reason makeUIView's registration above didn't take (e.g.
        // this view is recreated after boot already started), retry. Both calls are
        // idempotent - attach() ignores a container it already has, and
        // registerSurfaces() ignores everything once the TV surface exists.
        DisplayRouter.shared.attach(deviceContainer: uiView)
        DisplayRouter.shared.registerSurfaces(with: gameManager)
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
